import AppKit
import SwiftUI

@MainActor
final class MemoryMonitor: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshot?
    private var isSampling = false

    func refresh() {
        guard !isSampling else { return }
        isSampling = true
        let apps = RunningApp.current()
        Task {
            snapshot = await Task.detached(priority: .utility) {
                MemorySampler.sample(apps: apps)
            }.value
            isSampling = false
        }
    }
}

private struct MemoryContent: View {
    @ObservedObject var monitor: MemoryMonitor
    let quit: () -> Void

    var body: some View {
        MemoryView(snapshot: monitor.snapshot, refresh: monitor.refresh, quit: quit)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let monitor = MemoryMonitor()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MemoryContent(monitor: monitor, quit: { NSApp.terminate(nil) })
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            let icon = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "内存用量")
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "内存用量"
            button.setAccessibilityLabel("内存用量")
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // A transient popover only closes on outside clicks while the app is active,
            // and the search field only receives typing once the app is active.
            NSApp.activate()
        }
    }

    // The popover being shown is exactly "someone is looking", so sampling follows it.
    func popoverWillShow(_ notification: Notification) {
        startRefreshing()
    }

    func popoverDidClose(_ notification: Notification) {
        stopRefreshing()
    }

    private func startRefreshing() {
        guard timer == nil else { return }
        monitor.refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.monitor.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }
}

@main
enum RAMScope {
    @MainActor
    static func main() throws {
        if CommandLine.arguments.dropFirst().first == "--snapshot" {
            let snapshot = MemorySampler.sample(apps: RunningApp.current())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let json = try encoder.encode(snapshot)
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data([10]))
            return
        }

        // Menu bar only: LSUIElement in Info.plist keeps the app out of the Dock and the app switcher.
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
