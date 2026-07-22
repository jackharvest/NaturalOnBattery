import Cocoa
import IOKit.ps
import ServiceManagement

// MARK: - Scroll direction

// Same plist key System Settings > Trackpad > "Natural scrolling" writes to. The OS applies
// it live system-wide the moment it changes — no relaunch or logout needed, since direction
// is flipped at the HID event layer rather than cached per-app.
enum ScrollPreference {
    private static let key = "com.apple.swipescrolldirection" as CFString

    static func apply(natural: Bool) {
        CFPreferencesSetValue(key, natural ? kCFBooleanTrue : kCFBooleanFalse, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

// MARK: - Power source watching

final class PowerSourceWatcher {
    var onChange: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providingType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (providingType as String) == (kIOPSBatteryPowerValue as String)
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
}

// MARK: - Mode + settings

enum ScrollMode: String, CaseIterable {
    case automatic
    case alwaysNatural
    case alwaysClassic

    var title: String {
        switch self {
        case .automatic: return "Automatic (Natural on Battery)"
        case .alwaysNatural: return "Always Natural"
        case .alwaysClassic: return "Always Classic"
        }
    }
}

enum AppSettings {
    private static let modeKey = "scrollMode"
    private static let enabledKey = "enabled"

    static var mode: ScrollMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey) else { return .automatic }
            return ScrollMode(rawValue: raw) ?? .automatic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let watcher = PowerSourceWatcher()

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = AppDelegate.statusIcon
        }
        buildMenu()
        watcher.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        watcher.start()
        refresh()
    }

    private func buildMenu() {
        statusLine.isEnabled = false

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())

        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(modeMenuItem())
        menu.addItem(.separator())

        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(withTitle: "☕ Buy Me a Coffee", action: #selector(openBuyMeACoffee), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Uninstall NaturalOnBattery…", action: #selector(uninstall), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NaturalOnBattery", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func modeMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for mode in ScrollMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = AppSettings.mode == mode ? .on : .off
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ScrollMode(rawValue: raw) else { return }
        AppSettings.mode = mode
        sender.menu?.items.forEach { $0.state = ($0 == sender) ? .on : .off }
        refresh()
    }

    @objc private func toggleEnabled() {
        AppSettings.enabled = enabledItem.state != .on
        refresh()
    }

    private func refresh() {
        let onBattery = watcher.isOnBattery
        enabledItem.state = AppSettings.enabled ? .on : .off

        guard AppSettings.enabled else {
            statusLine.title = "Disabled"
            return
        }

        let natural: Bool
        switch AppSettings.mode {
        case .automatic: natural = onBattery
        case .alwaysNatural: natural = true
        case .alwaysClassic: natural = false
        }
        ScrollPreference.apply(natural: natural)

        let source = onBattery ? "on battery" : "on power"
        statusLine.title = "\(natural ? "Natural" : "Classic") scrolling — \(source)"
    }

    // Menu bar glyph stays fixed regardless of power state — it's the app's mark (same
    // arrow + battery motif as the Dock icon), not a live status indicator. The status
    // line in the menu itself is what reports current state; swapping the actual icon
    // between two SF Symbols read as an unrelated app switching, not one app changing mode.
    private static let statusIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            // Drawn as vector triangles rather than the "↕" character — at 18pt a font
            // glyph hints too thin/faint to read next to the battery below it.
            let midX = rect.midX
            let arrowWidth = rect.width * 0.42
            let arrowTopY = rect.height * 0.97
            let arrowBottomY = rect.height * 0.4
            let headHeight = (arrowTopY - arrowBottomY) * 0.45

            NSColor.black.setFill()
            let up = NSBezierPath()
            up.move(to: NSPoint(x: midX, y: arrowTopY))
            up.line(to: NSPoint(x: midX - arrowWidth / 2, y: arrowTopY - headHeight))
            up.line(to: NSPoint(x: midX + arrowWidth / 2, y: arrowTopY - headHeight))
            up.close()
            up.fill()

            let down = NSBezierPath()
            down.move(to: NSPoint(x: midX, y: arrowBottomY))
            down.line(to: NSPoint(x: midX - arrowWidth / 2, y: arrowBottomY + headHeight))
            down.line(to: NSPoint(x: midX + arrowWidth / 2, y: arrowBottomY + headHeight))
            down.close()
            down.fill()

            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: midX, y: arrowTopY - headHeight))
            stem.line(to: NSPoint(x: midX, y: arrowBottomY + headHeight))
            stem.lineWidth = rect.width * 0.1
            stem.lineCapStyle = .round
            stem.stroke()

            let batteryWidth = rect.width * 0.62
            let batteryHeight = rect.height * 0.22
            let batteryX = (rect.width - batteryWidth) / 2
            let batteryY = rect.height * 0.05
            let body = NSBezierPath(roundedRect: NSRect(x: batteryX, y: batteryY, width: batteryWidth, height: batteryHeight), xRadius: batteryHeight * 0.3, yRadius: batteryHeight * 0.3)
            body.lineWidth = 1.4
            NSColor.black.setStroke()
            body.stroke()

            let nubWidth = rect.width * 0.05
            let nub = NSBezierPath(roundedRect: NSRect(x: batteryX + batteryWidth, y: batteryY + batteryHeight * 0.25, width: nubWidth, height: batteryHeight * 0.5), xRadius: nubWidth * 0.4, yRadius: nubWidth * 0.4)
            NSColor.black.setFill()
            nub.fill()

            return true
        }
        image.isTemplate = true
        return image
    }()

    @objc private func toggleLoginItem() {
        do {
            if loginItem.state == .on {
                try SMAppService.mainApp.unregister()
                loginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                loginItem.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Login Item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openBuyMeACoffee() {
        if let url = URL(string: "https://buymeacoffee.com/jackharvest") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func uninstall() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall NaturalOnBattery?"
        alert.informativeText = "This removes NaturalOnBattery from Login Items, clears its saved settings, and moves NaturalOnBattery.app to the Trash. You can restore it from the Trash if you change your mind. Your current natural scrolling setting is left as-is."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? SMAppService.mainApp.unregister()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        let bundleURL = Bundle.main.bundleURL
        try? FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)

        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
