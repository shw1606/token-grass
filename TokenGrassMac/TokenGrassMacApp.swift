import SwiftUI
import AppKit
import Combine

@main
struct TokenGrassMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No window scene: this is a menu-bar-only (LSUIElement) app.
        Settings { EmptyView() }
    }
}

/// Owns the status-bar item so we can render a fixed-size label image (not
/// clipped to the menu-bar line the way a MenuBarExtra label is) and keep the
/// orange gauge while adapting the text color to the menu bar's appearance.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = UsageService()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(service: service))

        render()

        // Re-render the label whenever the usage data changes…
        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires *before* the value updates; defer a tick.
                DispatchQueue.main.async { self?.render() }
            }
            .store(in: &cancellables)

        // …and whenever the menu bar switches between light and dark.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.render() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        let renderer = ImageRenderer(content:
            MenuBarLabel(service: service)
                .environment(\.colorScheme, isDark ? .dark : .light)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = renderer.cgImage else { return }
        let scale = renderer.scale
        let image = NSImage(
            cgImage: cg,
            size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        )
        image.isTemplate = false // preserve the orange gauge
        button.image = image
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
