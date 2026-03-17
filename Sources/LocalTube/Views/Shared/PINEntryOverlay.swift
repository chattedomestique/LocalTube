import SwiftUI

struct PINEntryOverlay: View {
    @Environment(AppState.self) private var appState
    @State private var digits = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var showError = false
    @State private var showRecovery = false
    @State private var maxDigits: Int = 6

    var onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            LTScrimBackground()

            VStack(spacing: 40) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.ltAccent)

                    Text("Enter PIN")
                        .font(.ltHero)
                        .foregroundStyle(Color.ltText)
                }

                // Error message — always occupies space; opacity controls visibility
                Text("Incorrect PIN. Try again.")
                    .font(.ltCaption)
                    .foregroundStyle(Color.ltDestructive)
                    .opacity(showError ? 1 : 0)

                // Numpad
                NumpadView(digits: $digits, maxDigits: maxDigits, onCommit: verifyPIN)
                    .offset(x: shakeOffset)

                // Footer buttons — Cancel always occupies space; opacity controls visibility
                HStack(spacing: 24) {
                    Button("Forgot PIN?") {
                        showRecovery = true
                    }
                    .font(.ltCaption)
                    .foregroundStyle(Color.ltBlue)
                    .buttonStyle(.plain)

                    Button("Cancel") {
                        onCancel?()
                    }
                    .font(.ltCaption)
                    .foregroundStyle(Color.ltTextSecondary)
                    .buttonStyle(.plain)
                    .opacity(onCancel != nil ? 1 : 0)
                    .allowsHitTesting(onCancel != nil)
                }
            }
            .padding(60)
        }
        .onAppear {
            // Load the actual stored PIN length so entry auto-commits at the right digit count
            maxDigits = PINService.loadPin()?.count ?? 6
        }
        .sheet(isPresented: $showRecovery) {
            PINRecoveryView()
        }
    }

    private func verifyPIN(_ entered: String) {
        if PINService.verify(entered) {
            appState.enterEditorMode()
        } else {
            showError = true
            withAnimation(.default) {
                shakeOffset = 10
            }
            Task {
                for _ in 0..<4 {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    await MainActor.run {
                        withAnimation(.default) {
                            shakeOffset = shakeOffset > 0 ? -10 : 10
                        }
                    }
                }
                await MainActor.run {
                    withAnimation { shakeOffset = 0 }
                    digits = ""
                }
            }
        }
    }
}
