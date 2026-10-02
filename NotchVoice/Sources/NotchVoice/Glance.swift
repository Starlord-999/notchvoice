import IOBluetooth
import IOKit.ps
import SwiftUI

@MainActor final class Glance: ObservableObject {
    static let shared = Glance()
    @Published var cpu = 0.0
    @Published var ram = 0.0
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var battery: Int?
    @Published var charging = false
    @Published var bluetooth: [String] = []
    private var timer: Timer?
    private var lastTicks: [UInt32]?
    private var lastNet: (UInt32, UInt32)?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
    }

    func stop() { timer?.invalidate(); timer = nil; lastTicks = nil; lastNet = nil }

    private func poll() {
        // cpu
        var info = host_cpu_load_info()
        var n = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &n) }
        }
        if ok == KERN_SUCCESS {
            let t = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let l = lastTicks {
                let d = zip(t, l).map { Double($0 &- $1) }
                let total = d.reduce(0, +)
                if total > 0 { cpu = (total - d[2]) / total }
            }
            lastTicks = t
        }
        // ram
        var vm = vm_statistics64()
        var c = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c) }
        }
        if r == KERN_SUCCESS {
            ram = Double(UInt64(vm.active_count + vm.wire_count + vm.compressor_page_count) * UInt64(getpagesize())) / Double(ProcessInfo.processInfo.physicalMemory)
        }
        // network (bytes/s over en* interfaces)
        let net = Self.netBytes()
        if let l = lastNet { down = Double(net.0 &- l.0) / 2; up = Double(net.1 &- l.1) / 2 }
        lastNet = net
        // battery
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [CFTypeRef]
        battery = nil
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] {
                battery = d[kIOPSCurrentCapacityKey] as? Int
                charging = d[kIOPSIsChargingKey] as? Bool ?? false
            }
        }
        bluetooth = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }.compactMap(\.name)
    }

    private static func netBytes() -> (UInt32, UInt32) {
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifa) }
        var rx: UInt32 = 0, tx: UInt32 = 0
        var p = ifa
        while let i = p {
            let a = i.pointee
            if a.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let d = a.ifa_data, String(cString: a.ifa_name).hasPrefix("en") {
                let s = d.assumingMemoryBound(to: if_data.self).pointee
                rx &+= s.ifi_ibytes; tx &+= s.ifi_obytes
            }
            p = a.ifa_next
        }
        return (rx, tx)
    }
}

struct GlanceView: View {
    @ObservedObject var m = Glance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                gauge("CPU", m.cpu, .orange)
                gauge("RAM", m.ram, .purple)
                gauge("Battery", Double(m.battery ?? 0) / 100, m.charging ? .green : .blue, m.battery.map { "\($0)%" + (m.charging ? "⚡︎" : "") } ?? "–")
                VStack(alignment: .leading, spacing: 4) {
                    Label(speed(m.down), systemImage: "arrow.down")
                    Label(speed(m.up), systemImage: "arrow.up")
                }.font(.system(.caption, design: .monospaced)).frame(width: 110, alignment: .leading)
            }
            Label(m.bluetooth.isEmpty ? "No Bluetooth devices connected" : m.bluetooth.joined(separator: " · "), systemImage: "wave.3.right")
                .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
        }
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    func gauge(_ name: String, _ v: Double, _ c: Color, _ label: String? = nil) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: min(max(v, 0), 1)).stroke(c, style: .init(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(label ?? "\(Int(v * 100))%").font(.system(size: 11, weight: .medium, design: .rounded))
            }.frame(width: 56, height: 56)
            Text(name).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    func speed(_ b: Double) -> String { b > 1_000_000 ? String(format: "%.1f MB/s", b / 1e6) : String(format: "%.0f KB/s", b / 1e3) }
}
