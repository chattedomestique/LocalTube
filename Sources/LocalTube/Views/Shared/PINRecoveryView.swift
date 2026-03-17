import SwiftUI

struct PINRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = ""
    @State private var showError = false
    @State private var showPINSetup = false

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            VStack(spacing: 36) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.ltAccent)

                    Text("Forgot PIN?")
                        .font(.ltHero)
                        .foregroundStyle(Color.ltText)

                    Text("Enter your 4-word recovery phrase")
                        .font(.ltBody)
                        .foregroundStyle(Color.ltTextSecondary)
                        .multilineTextAlignment(.center)
                }

                // Recovery phrase input
                VStack(alignment: .leading, spacing: 12) {
                    TextField("maple river cloud seven", text: $phrase)
                        .font(.ltBody)
                        .foregroundStyle(Color.ltText)
                        .textFieldStyle(.plain)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: LT.buttonCornerRadius)
                                .fill(Color.ltSurface)
                        )
                        .autocorrectionDisabled()
                        .textContentType(.none)
                        .frame(maxWidth: 500)

                    if showError {
                        Text("Recovery phrase doesn't match. Please check and try again.")
                            .font(.ltCaption)
                            .foregroundStyle(Color.ltDestructive)
                    }
                }

                // Actions
                HStack(spacing: 20) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(LTSecondaryButtonStyle())

                    Button("Verify") {
                        verifyPhrase()
                    }
                    .buttonStyle(LTButtonStyle())
                    .disabled(phrase.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(60)
            .frame(maxWidth: 600)
        }
        .sheet(isPresented: $showPINSetup) {
            PINSetupView(isReset: true) {
                dismiss()
            }
        }
    }

    private func verifyPhrase() {
        let stored = PINService.loadRecoveryPhrase() ?? ""
        let entered = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let storedNorm = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if entered == storedNorm {
            showPINSetup = true
        } else {
            showError = true
        }
    }
}
