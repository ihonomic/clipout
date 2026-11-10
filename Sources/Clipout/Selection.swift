import AppKit
import ApplicationServices

/// Reads text selected in other apps. Needs the Accessibility permission.
@MainActor
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func askForPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Adds Clipout to the Accessibility list (once per signature) and opens
    /// the settings. Only on a click: asking at every launch was a nag.
    static func requestAccess() {
        askForPermission()
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Chrome and Electron apps only build their accessibility tree when asked.
    static func wakeAccessibility(of app: NSRunningApplication?) {
        guard let pid = app?.processIdentifier else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),
                                     "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// The selection, read directly. Works in most native apps, Safari and Chrome.
    static func selectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Role of the element under a screen point (AppKit coordinates).
    static func role(at point: NSPoint) -> String? {
        guard let screen = NSScreen.screens.first else { return nil }
        var element: AXUIElement?
        let flipped = Float(screen.frame.maxY - point.y)
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), flipped, &element) == .success,
              let element else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return role as? String
    }

    /// Title of the front window of the app, e.g. the PDF name in Preview.
    static func frontWindowTitle(of app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return title as? String
    }

    /// Fallback for apps that don't expose their selection (some PDF viewers,
    /// Electron apps): press ⌘C for the user, read the text, then put the
    /// clipboard back exactly as it was. PopClip does the same.
    static func copySelection(using monitor: ClipboardMonitor) async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        monitor.suspended = true
        defer {
            monitor.skipCurrentChange()
            monitor.suspended = false
        }
        pressCommandC()
        for _ in 0..<25 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func pressCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

/// Notices when the user finishes selecting text anywhere: a mouse drag or a
/// double/triple click.
@MainActor
final class SelectionWatcher {
    var onSelection: ((NSPoint, String?, NSRunningApplication?) -> Void)?
    var onMouseDown: ((NSPoint) -> Void)?

    private var monitors: [Any] = []
    private var downPoint = NSPoint.zero

    /// Dragging these moves windows, scrolls or rearranges things; it doesn't select text.
    private let nonTextRoles: Set<String> = [
        "AXWindow", "AXScrollBar", "AXSplitter", "AXToolbar", "AXButton", "AXMenuBar",
        "AXMenuBarItem", "AXTabGroup", "AXRadioButton", "AXSlider", "AXImage", "AXDockItem",
        "AXCheckBox", "AXPopUpButton", "AXIncrementor", "AXValueIndicator",
    ]
    private let ignoredApps: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow"]

    func start() {
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            Task { @MainActor in self?.mouseDown() }
        }) { monitors.append(down) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            let clicks = event.clickCount
            Task { @MainActor in self?.mouseUp(clicks: clicks) }
        }) { monitors.append(up) }
    }

    private func mouseDown() {
        downPoint = NSEvent.mouseLocation
        onMouseDown?(downPoint)
    }

    private func mouseUp(clicks: Int) {
        let upPoint = NSEvent.mouseLocation
        let dragged = hypot(upPoint.x - downPoint.x, upPoint.y - downPoint.y) > 6
        guard dragged || clicks >= 2, Prefs.showIcon, SelectionReader.isTrusted else { return }
        let app = NSWorkspace.shared.frontmostApplication
        guard let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              !ignoredApps.contains(id) else { return }
        let start = downPoint
        Task {
            try? await Task.sleep(for: .milliseconds(120))   // let the app update its selection
            SelectionReader.wakeAccessibility(of: app)
            let text = SelectionReader.selectedText()
            if text == nil {
                // Unknown selection: only offer the icon where text is likely,
                // and read it later with ⌘C if the user clicks.
                guard Prefs.copyFallback else { return }
                if let role = SelectionReader.role(at: start), nonTextRoles.contains(role) { return }
            }
            onSelection?(upPoint, text, app)
        }
    }
}
