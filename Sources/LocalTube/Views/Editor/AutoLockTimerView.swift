import SwiftUI

struct AutoLockTimerView: View {
    @Environment(AppState.self) private var appState

    private var remaining: Int { appState.editorRemainingSeconds }
    private var isUrgent: Bool { remaining <= 60 }
    private var isCritical: Bool { remaining <= 10 }

    var body: some View {
        Button(action: { appState.resetEditorLockTimer() }) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 16))
                Text("Auto-lock \(formattedTime)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(labelColor.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Editor Mode auto-locks in \(formattedTime). Tap to reset.")
    }

    private var formattedTime: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private var labelColor: Color {
        if isCritical { return .ltDestructive }
        if isUrgent { return .ltAccent }
        return .ltTextSecondary
    }
}
