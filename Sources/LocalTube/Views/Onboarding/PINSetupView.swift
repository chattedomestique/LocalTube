import SwiftUI

/// Multi-step PIN setup flow used on first launch and for PIN reset.
struct PINSetupView: View {
    var isReset: Bool = false
    var onComplete: (() -> Void)?

    @Environment(AppState.self) private var appState
    @State private var step: Step = .enterPIN
    @State private var firstPIN = ""
    @State private var confirmPIN = ""
    @State private var mismatch = false
    @State private var recoveryPhrase = ""

    enum Step { case enterPIN, confirmPIN, showRecovery }

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            VStack(spacing: 40) {
                switch step {
                case .enterPIN:
                    enterPINStep

                case .confirmPIN:
                    confirmPINStep

                case .showRecovery:
                    recoveryStep
                }
            }
            .padding(60)
            .animation(.easeInOut(duration: 0.2), value: step)
        }
    }

    // MARK: - Steps

    private var enterPINStep: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: isReset ? "key.fill" : "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.ltAccent)

                Text(isReset ? "Create New PIN" : "Set a Parent PIN")
                    .font(.ltHero)
                    .foregroundStyle(Color.ltText)

                Text("Choose a 4–6 digit PIN to protect Editor Mode")
                    .font(.ltBody)
                    .foregroundStyle(Color.ltTextSecondary)
                    .multilineTextAlignment(.center)
            }

            NumpadView(digits: $firstPIN, maxDigits: 6) { pin in
                guard pin.count >= 4 else { return }
                confirmPIN = ""
                mismatch = false
                step = .confirmPIN
            }

            // Always present so the numpad never shifts; visible only when a 4- or 5-digit
            // PIN has been entered (the user can commit early instead of waiting for 6 digits).
            Button("Use \(firstPIN.count < 4 ? 4 : firstPIN.count)-digit PIN") {
                confirmPIN = ""
                mismatch = false
                step = .confirmPIN
            }
            .buttonStyle(LTSecondaryButtonStyle())
            .opacity(firstPIN.count >= 4 && firstPIN.count < 6 ? 1 : 0)
            .allowsHitTesting(firstPIN.count >= 4 && firstPIN.count < 6)
        }
    }

    private var confirmPINStep: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.ltAccent)

                Text("Confirm PIN")
                    .font(.ltHero)
                    .foregroundStyle(Color.ltText)

                Text("Enter your PIN again to confirm")
                    .font(.ltBody)
                    .foregroundStyle(Color.ltTextSecondary)
            }

            // Always present; opacity controls visibility so the numpad never shifts
            Text("PINs don't match — try again")
                .font(.ltCaption)
                .foregroundStyle(Color.ltDestructive)
                .opacity(mismatch ? 1 : 0)

            NumpadView(digits: $confirmPIN, maxDigits: firstPIN.count) { pin in
                if pin == firstPIN {
                    savePINAndContinue(pin)
                } else {
                    mismatch = true
                    confirmPIN = ""
                }
            }

            Button("Back") {
                firstPIN = ""
                confirmPIN = ""
                mismatch = false
                step = .enterPIN
            }
            .font(.ltCaption)
            .foregroundStyle(Color.ltTextSecondary)
            .buttonStyle(.plain)
        }
    }

    private var recoveryStep: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.ltAccent)

                Text("Write This Down")
                    .font(.ltHero)
                    .foregroundStyle(Color.ltText)

                Text("If you ever forget your PIN, use these 4 words to reset it. This is shown once — write it somewhere safe.")
                    .font(.ltBody)
                    .foregroundStyle(Color.ltTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            // Recovery phrase display
            Text(recoveryPhrase)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ltAccent)
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: 500)
                .background(
                    RoundedRectangle(cornerRadius: LT.cardCornerRadius)
                        .fill(Color.ltSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: LT.cardCornerRadius)
                                .strokeBorder(Color.ltAccent.opacity(0.4), lineWidth: 2)
                        )
                )

            Button("I've Written It Down — Let's Go!") {
                appState.needsPINSetup = false
                onComplete?()
            }
            .buttonStyle(LTButtonStyle())
        }
    }

    // MARK: - Save

    private func savePINAndContinue(_ pin: String) {
        let phrase = PINService.generateRecoveryPhrase()
        try? PINService.savePin(pin, recoveryPhrase: phrase)
        recoveryPhrase = phrase
        step = .showRecovery
    }
}
