import SwiftUI

/// In-memory only (never written to disk). Skips password-manager / transient pasteboard items.
@MainActor final class Clips: ObservableObject {
    static let shared = Clips()
    @Published var items: [String] = []
    private var last = NSPasteboard.general.changeCount

    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != last else { return }
        last = pb.changeCount
        let hidden: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        guard !(pb.types ?? []).contains(where: { hidden.contains($0.rawValue) }),
              let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 30 { items.removeLast() }
    }

    func find(_ q: String) -> String? { items.first { $0.localizedCaseInsensitiveContains(q) } }

    func paste(_ s: String) {
        Task { _ = await Actions.type(s, into: nil) }
    }
}

struct ClipboardView: View {
    @ObservedObject var m = Clips.shared
    @State var q = ""

    var shown: [String] { q.isEmpty ? m.items : m.items.filter { $0.localizedCaseInsensitiveContains(q) } }

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search clipboard", text: $q).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(shown, id: \.self) { s in
                        Button { m.paste(s) } label: {
                            Text(s).lineLimit(1).font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
