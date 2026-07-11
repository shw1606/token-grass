import SwiftUI
import AppKit
import Combine
import Sparkle

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
    // startingUpdater: true begins Sparkle's background schedule immediately
    // (interval set via SUScheduledCheckInterval in Info.plist) — no separate
    // "start" call needed.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private lazy var updaterViewModel = UpdaterViewModel(updaterController: updaterController)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var lastRenderKey = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover.behavior = .transient
        // Let the popover track the SwiftUI content's ideal size instead of a
        // fixed contentSize — MenuContentView's width shrinks in calendar mode
        // (small, grid-fit cells), and we want the popover itself to shrink
        // with it rather than leaving empty space.
        let hosting = NSHostingController(
            rootView: MenuContentView(service: service, onOpenSettings: { [weak self] in self?.showSettings() })
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

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

        // …and when the menu-bar display options change in Settings. render()
        // dedups by key, so most notifications are cheap no-ops.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.render() }

        #if DEBUG
        if ProcessInfo.processInfo.environment["TG_RENDER_SAMPLES"] == "1" { renderLabelSamples() }
        #endif
    }

    #if DEBUG
    private func renderLabelSamples() {
        service.debugSeedUsage(fiveHour: 42, sevenDay: 18)
        let combos: [(Bool, Bool, String)] = [
            (true, true, "grass+both"), (true, false, "grass+5h"),
            (false, true, "nogr+both"), (false, false, "nogr+5h"),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            for (g, w, name) in combos {
                let r = ImageRenderer(content:
                    MenuBarLabel(service: self.service, showGrass: g, showWeekly: w)
                        .environment(\.colorScheme, .light)
                        .padding(6).background(Color.white)
                )
                r.scale = 6
                if let cg = r.cgImage,
                   let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: "/tmp/tg-label-\(name).png"))
                    SyncLog.log("TEST render \(name): OK \(cg.width)x\(cg.height)")
                } else {
                    SyncLog.log("TEST render \(name): FAILED (nil cgImage)")
                }
            }
        }
    }
    #endif

    private func render() {
        guard let button = statusItem.button else { return }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let defaults = UserDefaults.standard
        // Default true when unset: object(forKey:) is nil → showGrass/showWeekly true.
        let showGrass = defaults.object(forKey: "tokengrass.menubar.showGrass") as? Bool ?? true
        let showWeekly = defaults.object(forKey: "tokengrass.menubar.showWeekly") as? Bool ?? true

        // Only rebuild the image when what it shows actually changes. Crucial: the
        // last line sets `button.image`, which itself re-notifies `effectiveAppearance`
        // — without this guard the appearance observer would re-enter render() forever
        // and peg a CPU core at 100%.
        let key = "\(isDark)|\(Int(service.fiveHour.rounded()))|\(Int(service.sevenDay.rounded()))|\(service.lastSync != nil)|\(showGrass)|\(showWeekly)"
        guard key != lastRenderKey else { return }
        lastRenderKey = key

        let renderer = ImageRenderer(content:
            MenuBarLabel(service: service, showGrass: showGrass, showWeekly: showWeekly)
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

    /// Open (or focus) the Settings window. A menu-bar-only app has no window by
    /// default, so we own an NSWindow hosting SettingsView and bring it forward.
    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(service: service, updater: updaterViewModel)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "TokenGrass 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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

/// Thin SwiftUI-facing wrapper around Sparkle's updater. No manual "check now"
/// button — updates are silent/automatic (Sparkle surfaces its own alert when
/// it finds one); the only user-facing control is whether background checks
/// (every SUScheduledCheckInterval) happen at all. Sparkle persists this
/// choice itself (SUEnableAutomaticChecks in the app's own defaults).
@MainActor
final class UpdaterViewModel: ObservableObject {
    private let updater: SPUUpdater

    @Published var automaticallyChecksForUpdates: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init(updaterController: SPUStandardUpdaterController) {
        updater = updaterController.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
}
