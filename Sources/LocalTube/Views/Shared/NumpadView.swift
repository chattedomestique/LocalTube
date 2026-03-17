import SwiftUI

/// Reusable large-format numpad for PIN entry (ten-foot friendly).
struct NumpadView: View {
    @Binding var digits: String
    var maxDigits: Int = 6
    var onCommit: ((String) -> Void)?

    private let rows: [[String?]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [nil, "0", "⌫"],
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Dot indicators — fixed height so the numpad never shifts when fill state changes
            HStack(spacing: 20) {
                ForEach(0..<maxDigits, id: \.self) { i in
                    Circle()
                        .fill(Color.ltSurface)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.ltAccent.opacity(0.6), lineWidth: 2)
                        )
                        .overlay(
                            Circle()
                                .fill(Color.ltAccent)
                                .frame(width: 20, height: 20)
                                .opacity(i < digits.count ? 1 : 0)
                        )
                }
            }
            .frame(height: 28)
            .padding(.bottom, 8)

            // Numpad grid
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row.indices, id: \.self) { idx in
                        if let key = row[idx] {
                            NumpadKeyView(key: key) {
                                handleKey(key)
                            }
                        } else {
                            Color.clear
                                .frame(width: LT.minTargetSize, height: LT.minTargetSize)
                        }
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !digits.isEmpty { digits.removeLast() }
        } else if digits.count < maxDigits {
            digits.append(key)
            if digits.count == maxDigits {
                onCommit?(digits)
            }
        }
    }
}

private struct NumpadKeyView: View {
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key)
                .font(.ltNumpad)
                .foregroundStyle(Color.ltText)
                .frame(width: LT.minTargetSize, height: LT.minTargetSize)
                .background(
                    RoundedRectangle(cornerRadius: LT.buttonCornerRadius)
                        .fill(Color.ltSurface)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key == "⌫" ? "Backspace" : key)
    }
}

#Preview {
    NumpadView(digits: .constant("123"))
        .padding()
        .background(Color.ltBackground)
}
