import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    let store = UsageStore()
    private var compactBodySize = NSSize(width: 220, height: 40)
    private var compactPanelSize = NSSize(width: 228, height: 44)
    private var notchCenterX: CGFloat?
    private var targetScreen: NSScreen?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DispatchQueue.main.async { self.showPanel() }
    }

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: AppSettingsView(store: store))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Codex Notch 设置"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            settingsWindow = window
        } else {
            settingsWindow?.contentViewController = NSHostingController(rootView: AppSettingsView(store: store))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showPanel() {
        let screen = NotchScreen.preferred()
        targetScreen = screen
        if let screen { updateScreenMetrics(screen) }
        let content = NotchRootView(
            store: store,
            compactBodyHeight: compactBodySize.height,
            onResize: { [weak self] expanded in self?.resize(expanded: expanded) },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
#if DEBUG
        panel.sharingType = .readOnly
#endif
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        if let panelLayer = panel.contentView?.layer {
            panelLayer.masksToBounds = false
            panelLayer.backgroundColor = NSColor.clear.cgColor
        }
        self.panel = panel
        resize(expanded: false)
        panel.orderFrontRegardless()
    }

    private func resize(expanded: Bool) {
        guard let panel else { return }
        let screen = NotchScreen.preferred() ?? targetScreen ?? NSScreen.main
        guard let screen else { return }
        targetScreen = screen
        updateScreenMetrics(screen)
        let size = expanded ? NotchMetrics.expandedPanelSize : compactPanelSize
        let centerX = notchCenterX ?? screen.frame.midX
        let frame = NSRect(
            x: centerX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true, animate: true)
    }

    @objc private func screensChanged() {
        resize(expanded: panel.map { $0.frame.height > compactPanelSize.height + 8 } ?? false)
    }

    private func updateScreenMetrics(_ screen: NSScreen) {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else {
            compactBodySize = NotchMetrics.collapsedSize(notchWidth: 0, safeTop: 0)
            compactPanelSize = NotchMetrics.compactPanelSize(notchWidth: 0, safeTop: 0)
            notchCenterX = screen.frame.midX
            return
        }
        let notchWidth = right.minX - left.maxX
        compactBodySize = NotchMetrics.collapsedSize(notchWidth: notchWidth, safeTop: screen.safeAreaInsets.top)
        compactPanelSize = NotchMetrics.compactPanelSize(notchWidth: notchWidth, safeTop: screen.safeAreaInsets.top)
        notchCenterX = (left.maxX + right.minX) / 2
    }
}

enum NotchScreen {
    static func preferred() -> NSScreen? {
        let screens = NSScreen.screens
        let notched = screens.filter(\.hasHardwareNotch)
        if let builtInNotched = notched.first(where: \.isBuiltinDisplay) {
            return builtInNotched
        }
        if let anyNotched = notched.first {
            return anyNotched
        }
        if let builtIn = screens.first(where: \.isBuiltinDisplay) {
            return builtIn
        }
        return NSScreen.main ?? screens.first
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltinDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    var hasHardwareNotch: Bool {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea,
              right.minX > left.maxX else {
            return false
        }
        return safeAreaInsets.top > 0
    }
}
