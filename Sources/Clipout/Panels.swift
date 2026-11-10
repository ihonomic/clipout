import AppKit
import SwiftUI

/// Hosting view that reacts to the first click even though its panel never
/// becomes key (the app the user is reading in keeps focus and selection).
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Small borderless panel that floats over every app and space without
/// taking focus: used for the "+ Anki" icon and short messages.
final class FloatingPanel: NSPanel {
    init<Content: View>(size: NSSize, content: Content) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = FirstClickHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the panel next to a screen point, kept inside that screen.
    func show(near point: NSPoint, offset: NSPoint = NSPoint(x: 8, y: 10)) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x + offset.x, y: point.y + offset.y)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
    }
}

struct SelectionIcon: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus.rectangle.on.rectangle")
                Text("Anki")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .help(L("Karte aus der Markierung erstellen (⌥⌘A)"))
        .padding(4)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(6)
            .fixedSize()
    }
}

/// Ordinary window (with keyboard focus) for the card composer and settings.
@MainActor
func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.contentView = NSHostingView(rootView: content)
    window.center()
    return window
}
