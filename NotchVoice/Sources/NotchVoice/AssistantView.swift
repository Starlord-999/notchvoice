import SwiftUI

/// Content of the opened notch.
struct AssistantView: View {
    @StateObject var vm: NotchViewModel
    @ObservedObject var assistant: Assistant

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                    .animation(.easeInOut, value: dotColor)
                Text("Notch").font(.system(.headline, design: .rounded))
                Spacer()
                if let name = assistant.fileName {
                    Label(name, systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                        .font(.system(.caption, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                        .frame(maxWidth: 260, alignment: .trailing)
                }
            }
            Text(!assistant.live.isEmpty ? assistant.live : assistant.heard.isEmpty ? "Press Type or Command, or say “Hey Notch…”" : "“\(assistant.heard)”")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(assistant.live.isEmpty && assistant.heard.isEmpty ? .secondary : .primary)
                .lineLimit(3)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                modeButton("keyboard", "Type  ⌥Space", assistant.typeLocked, .green) { assistant.toggleType() }
                modeButton("mic", "Command  ⌥⇧Space", assistant.commandLocked, .blue) { assistant.toggleCommand() }
                Spacer()
                Text(assistant.status)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func modeButton(_ icon: String, _ title: String, _ on: Bool, _ c: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(.caption, design: .rounded).weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? c.opacity(0.85) : .white.opacity(0.12), in: Capsule())
        }.buttonStyle(.plain)
    }

    var dotColor: Color {
        if assistant.hearing { return .green }
        if assistant.speaking { return .blue }
        if assistant.thinking { return .orange }
        return .gray
    }
}
