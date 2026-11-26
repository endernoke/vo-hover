// VOHover — speaks the accessibility item under the mouse pointer through
// VoiceOver's own speech, without moving the VoiceOver cursor.
//
// Toggle on/off:  pkill -USR1 -x VOHover   (bind via VoiceOver Commands > Run AppleScript)
// Launch flag:    --background   start without opening Settings
// Debug log:      log stream --level debug --predicate 'subsystem == "io.github.endernoke.vohover"'

import Cocoa
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let engine = HoverEngine()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var toggleSignal: DispatchSourceSignal?
    private var titleSubscription: AnyCancellable?
    private var launchedInBackground = CommandLine.arguments.contains("--background")
    private var lastEnabled = Prefs.enabled

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Launched as a login item → stay in the background.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            launchedInBackground = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()

        // SIGUSR1 (sent by the Toggle VOHover script) toggles hover speech.
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.toggleEnabled() }
        src.resume()
        toggleSignal = src

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        ToggleScript.installIfNeeded()
        updateStatusItem()
        engine.start()
        if !launchedInBackground { showSettings(nil) }
    }

    // Opening the app again from Finder/Spotlight shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    // MARK: Enable / disable

    @objc private func defaultsChanged() {
        // May be posted on any thread.
        DispatchQueue.main.async { [self] in
            if Prefs.enabled != lastEnabled {
                lastEnabled = Prefs.enabled
                engine.reset()
                VoiceOver.say(Prefs.enabled ? "Hover speech on" : "Hover speech off")
            }
            updateStatusItem()
        }
    }

    @objc private func toggleEnabled() {
        Prefs.enabled.toggle()   // defaultsChanged() announces the change
    }

    // MARK: Menu bar item

    private func updateStatusItem() {
        guard Prefs.showInMenuBar else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "VOHover")
            item.button?.setAccessibilityLabel("VOHover")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        statusItem?.button?.appearsDisabled = !Prefs.enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Speak Item Under Pointer", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = Prefs.enabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "VOHover Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit VOHover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: Settings window

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.toolbar = NSToolbar(identifier: "settings")
            w.setContentSize(NSSize(width: 715, height: 520))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("VOHoverSettings")
            if !w.setFrameUsingName("VOHoverSettings") { w.center() }
            // Like System Settings: the window title names the selected category.
            titleSubscription = SettingsModel.shared.$selection.sink { [weak w] pane in
                w?.title = (pane ?? .general).title
            }
            settingsWindow = w
        }
        // Behave like a normal app (Dock, Command-Tab) while Settings is open.
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About VOHover", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide VOHover", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit VOHover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        let main = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}

Prefs.registerDefaults()
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
