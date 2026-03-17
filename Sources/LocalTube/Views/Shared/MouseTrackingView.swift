import AppKit
import SwiftUI

// MARK: - Mouse Position Reader
// Reports cursor position (in SwiftUI top-left coordinates) and hover state
// for the view bounds. Uses NSTrackingArea so it works independently of
// SwiftUI's hit-testing — clicks still pass through to underlying buttons.

struct MousePositionReader: NSViewRepresentable {
    @Binding var position: CGPoint
    @Binding var isInside: Bool

    func makeNSView(context: Context) -> LTMouseTrackingNSView {
        let v = LTMouseTrackingNSView()
        v.onMove  = { pos in position = pos }
        v.onEnter = { pos in isInside = true;  position = pos }
        v.onExit  = {        isInside = false }
        return v
    }

    func updateNSView(_ nsView: LTMouseTrackingNSView, context: Context) {}
}

// MARK: - Underlying NSView

final class LTMouseTrackingNSView: NSView {
    var onMove:  ((CGPoint) -> Void)?
    var onEnter: ((CGPoint) -> Void)?
    var onExit:  (() -> Void)?

    override var acceptsFirstResponder: Bool { false }

    // Don't consume clicks — pass them up the responder chain
    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let opts: NSTrackingArea.Options = [
            .activeInActiveApp,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        addTrackingArea(NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil))
    }

    /// Convert AppKit event location to SwiftUI coordinate space (top-left origin).
    private func swiftUIPoint(for event: NSEvent) -> CGPoint {
        let pt = convert(event.locationInWindow, from: nil)
        return CGPoint(x: pt.x, y: bounds.height - pt.y)
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(swiftUIPoint(for: event))
    }
    override func mouseEntered(with event: NSEvent) {
        onEnter?(swiftUIPoint(for: event))
    }
    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}
