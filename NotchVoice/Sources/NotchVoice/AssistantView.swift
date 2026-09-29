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
            Text(assistant.heard.isEmpty ? "Drop a file here, or say “Hey Notch…”" : "“\(assistant.heard)”")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(assistant.heard.isEmpty ? .secondary : .primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(assistant.status)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var dotColor: Color {
        if assistant.hearing { return .green }
        if assistant.speaking { return .blue }
        if assistant.thinking { return .orange }
        return .gray
    }
}
