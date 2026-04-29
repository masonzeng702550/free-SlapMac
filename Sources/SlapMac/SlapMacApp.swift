import SwiftUI
import AppKit

@main
enum SlapMacMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let detector = SlapDetector()
    let hidDetector = HIDMotionDetector()
    let pack = SoundPack()
    let config = DetectionConfig()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var showSettings: Bool = false {
        didSet { if showSettings { openSettings() } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[SlapMac] launching")
        NSApp.setActivationPolicy(.accessory)

        // 兩個引擎皆接到同一個播放函式。
        let playHandler: (Float) -> Void = { [weak self] intensity in
            self?.pack.playRandom(intensity: intensity)
        }
        detector.onSlap = playHandler
        hidDetector.onSlap = playHandler

        // 模式切換時啟動/停止對應 detector。
        config.onChange = { [weak self] mode in
            self?.applyMode(mode)
        }

        // 建立選單列 item。
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill",
                                   accessibilityDescription: "SlapMac")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            NSLog("[SlapMac] status item created")
        } else {
            NSLog("[SlapMac] WARNING: status item button is nil")
        }

        // 建立 popover。
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 420)
        let binding = Binding<Bool>(
            get: { self.showSettings },
            set: { self.showSettings = $0 }
        )
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(showSettings: binding)
                .environmentObject(detector)
                .environmentObject(hidDetector)
                .environmentObject(pack)
                .environmentObject(config)
        )

        // 依設定啟動對應引擎。
        applyMode(config.mode)

        // 首次執行若沒音效，直接開啟設定視窗提示用戶。
        if pack.entries.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        detector.stop()
        hidDetector.stop()
        pack.stopAll()
    }

    private func applyMode(_ mode: DetectionConfig.Mode) {
        switch mode {
        case .microphone:
            hidDetector.stop()
            detector.start()
        case .accelerometer:
            detector.stop()
            hidDetector.start()
        case .both:
            detector.start()
            hidDetector.start()
        }
        NSLog("[SlapMac] mode=\(mode.rawValue) mic=\(detector.isRunning) hid=\(hidDetector.isRunning)")
    }

    @objc private func togglePopover(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: detector.isRunning ? "停用偵測" : "啟用偵測",
            action: #selector(toggleDetector), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let settings = NSMenuItem(
            title: "管理音效庫…",
            action: #selector(openSettingsAction), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "離開 SlapMac",
            action: #selector(quit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleDetector() {
        let anyRunning = detector.isRunning || hidDetector.isRunning
        if anyRunning {
            detector.stop()
            hidDetector.stop()
        } else {
            applyMode(config.mode)
        }
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func openSettings() {
        showSettings = false
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsView()
            .environmentObject(detector)
            .environmentObject(hidDetector)
            .environmentObject(pack)
            .environmentObject(config)
        let hosting = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: hosting)
        w.title = "SlapMac 設定"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 560, height: 520))
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[SlapMac] settings window opened")
    }
}
