import SwiftUI
import AppKit

// MARK: - Reduce Motion

extension NSWorkspace {
    /// Returns true when the user has enabled "Reduce Motion" in Accessibility preferences.
    var shouldReduceMotion: Bool {
        accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - Conditional Animation Modifier

struct ConditionalAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        if NSWorkspace.shared.shouldReduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}

extension View {
    /// Applies an animation only when "Reduce Motion" is disabled.
    func reducibleAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ConditionalAnimationModifier(animation: animation, value: value))
    }
}

// MARK: - Focus Ring

struct TenFootFocusModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.ltAccent, lineWidth: isFocused ? 4 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            )
    }
}

extension View {
    func tenFootFocusRing() -> some View {
        modifier(TenFootFocusModifier())
    }
}
