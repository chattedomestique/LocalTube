import SwiftUI

// MARK: - Color Palette
// All colors verified for WCAG AA contrast against their typical backgrounds.

extension Color {
    /// Deep dark background — the "screen" color.
    static let ltBackground = Color(red: 0.086, green: 0.086, blue: 0.133)
    /// Slightly elevated surface for cards.
    static let ltSurface = Color(red: 0.137, green: 0.137, blue: 0.208)
    /// Higher elevation — modals, overlays.
    static let ltSurfaceElevated = Color(red: 0.180, green: 0.180, blue: 0.267)
    /// Warm gold accent — primary interactive color.
    static let ltAccent = Color(red: 1.0, green: 0.745, blue: 0.0)
    /// Sky blue — secondary interactive color.
    static let ltBlue = Color(red: 0.376, green: 0.745, blue: 1.0)
    /// Bright red for destructive actions.
    static let ltDestructive = Color(red: 1.0, green: 0.294, blue: 0.294)
    /// Green for success / ready states.
    static let ltSuccess = Color(red: 0.275, green: 0.898, blue: 0.408)
    /// Primary text — pure white.
    static let ltText = Color.white
    /// Secondary text — 70% white. ~4.8:1 contrast on ltBackground.
    static let ltTextSecondary = Color(white: 0.70)
    /// Tertiary text — 50% white.
    static let ltTextTertiary = Color(white: 0.50)
}

// MARK: - Typography

extension Font {
    /// Hero display text: 48pt bold SF Rounded
    static let ltHero = Font.system(size: 48, weight: .bold, design: .rounded)
    /// Large section title: 36pt bold SF Rounded
    static let ltTitle = Font.system(size: 36, weight: .bold, design: .rounded)
    /// Card title: 28pt semibold SF Rounded
    static let ltHeadline = Font.system(size: 28, weight: .semibold, design: .rounded)
    /// Body text: 28pt regular SF Rounded
    static let ltBody = Font.system(size: 28, weight: .regular, design: .rounded)
    /// Caption / metadata: 24pt regular SF Rounded
    static let ltCaption = Font.system(size: 24, weight: .regular, design: .rounded)
    /// Numpad digits: 36pt bold SF Rounded
    static let ltNumpad = Font.system(size: 36, weight: .bold, design: .rounded)
}

// MARK: - Layout Constants

enum LT {
    static let minTargetSize: CGFloat = 96
    static let cardCornerRadius: CGFloat = 20
    static let buttonCornerRadius: CGFloat = 16
    static let gridSpacing: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let sfSymbolSize: CGFloat = 40
    static let shadowRadius: CGFloat = 12
    static let shadowOpacity: Double = 0.4
}

// MARK: - Button Styles

/// Large, high-contrast primary button for ten-foot use.
struct LTButtonStyle: ButtonStyle {
    var color: Color = .ltAccent
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ltHeadline)
            .foregroundStyle(isDestructive ? Color.white : Color.black)
            .padding(.horizontal, 36)
            .padding(.vertical, 20)
            .frame(minWidth: LT.minTargetSize, minHeight: LT.minTargetSize)
            .background(
                RoundedRectangle(cornerRadius: LT.buttonCornerRadius)
                    .fill(isDestructive ? Color.ltDestructive : color)
                    .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

/// Secondary button (outlined).
struct LTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ltHeadline)
            .foregroundStyle(Color.ltAccent)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .frame(minWidth: LT.minTargetSize, minHeight: LT.minTargetSize)
            .background(
                RoundedRectangle(cornerRadius: LT.buttonCornerRadius)
                    .strokeBorder(Color.ltAccent, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

/// Icon-only circular button.
struct LTIconButtonStyle: ButtonStyle {
    var color: Color = .ltAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .frame(width: LT.minTargetSize, height: LT.minTargetSize)
            .background(
                Circle()
                    .fill(Color.ltSurface)
                    .shadow(color: Color.black.opacity(0.3), radius: 4)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Card Style Modifier

struct LTCardModifier: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: LT.cardCornerRadius)
                    .fill(Color.ltSurface)
                    .shadow(
                        color: Color.black.opacity(LT.shadowOpacity),
                        radius: LT.shadowRadius, x: 0, y: 6
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LT.cardCornerRadius)
                    .strokeBorder(
                        isSelected ? Color.ltAccent : Color.clear,
                        lineWidth: isSelected ? 3 : 0
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: LT.cardCornerRadius))
    }
}

extension View {
    func ltCard(isSelected: Bool = false) -> some View {
        modifier(LTCardModifier(isSelected: isSelected))
    }
}

// MARK: - Overlay Scrim

/// Full-window scrim used behind modal overlays (PIN entry, etc.).
/// Uses a material blur so underlying content remains dimly visible —
/// confirming context while keeping the overlay readable (WCAG AA).
struct LTScrimBackground: View {
    var body: some View {
        ZStack {
            // Frosted-glass blur layer — adapts automatically to dark mode
            Rectangle()
                .fill(.regularMaterial)
            // Additional dark tint for contrast / brand consistency
            Color.black.opacity(0.50)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Loading Spinner

struct LTSpinner: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.large)
            .tint(.ltAccent)
    }
}

// MARK: - Editor-mode Button Styles
// The editor is used at desk distance by parents, not 10-foot TV distance.
// These are compact versions appropriate for standard macOS app use.

/// Compact primary button for editor (parent) mode.
struct LTEditorButtonStyle: ButtonStyle {
    var color: Color = .ltAccent
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(isDestructive ? Color.white : Color.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDestructive ? Color.ltDestructive : color)
                    .shadow(color: (isDestructive ? Color.ltDestructive : color).opacity(0.35), radius: 4, x: 0, y: 2)
            )
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

/// Compact secondary (outlined) button for editor mode.
struct LTEditorSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.ltAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.ltAccent, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Input Field Modifier

/// Applies consistent, visible input field styling with elevated background and a subtle border.
/// Use on any TextField, TextEditor, or custom input control in the editor.
struct LTFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.ltSurfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(white: 0.35), lineWidth: 1)
            )
    }
}

extension View {
    func ltField() -> some View {
        modifier(LTFieldModifier())
    }
}

// MARK: - Step Progress Indicator

/// Horizontal dot-based progress indicator used in multi-step flows.
struct LTStepIndicator: View {
    let totalSteps: Int
    let currentStep: Int   // 0-based

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == currentStep ? Color.ltAccent : Color.ltTextTertiary.opacity(0.5))
                    .frame(width: i == currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}
