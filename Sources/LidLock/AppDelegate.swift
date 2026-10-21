import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Identifies the cat item without tying the lookup to its title.
    private static let catGuardTag = 1
    /// Same idea for the lock item, whose shortcut is redrawn as it changes.
    private static let lockTag = 2

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.setAccessibilityLabel("LidLock")
        statusItem.menu = buildMenu()

        CatGuard.shared.onPaw = { [weak self] in self?.catDetected() }
        CatGuard.shared.refresh()

        Hotkey.shared.onFire = { [weak self] in self?.lockNow() }
        Hotkey.shared.register(Preferences.lockShortcut)

        if AppDelegate.isTranslocated {
            DispatchQueue.main.async { AppDelegate.warnAboutTranslocation() }
            return
        }

        if PinStore.load() == nil {
            // Deferred: an accessory app cannot reliably take focus during launch.
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        LockController.shared.isLocked ? .terminateCancel : .terminateNow
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let lock = NSMenuItem(title: "Lock for Cleaning", action: #selector(lockNow), keyEquivalent: "")
        lock.target = self
        lock.tag = AppDelegate.lockTag
        menu.addItem(lock)

        let catGuard = NSMenuItem(title: "🐾 Watch for Cats", action: #selector(toggleCatGuard), keyEquivalent: "")
        catGuard.target = self
        catGuard.tag = AppDelegate.catGuardTag
        menu.addItem(catGuard)

        menu.addItem(.separator())

        // No key equivalents on these two: a menu bar accessory has no main
        // menu, so they would only ever work with the menu already open —
        // drawn like a shortcut, useless as one.
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit LidLock", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - App translocation

    /// macOS runs a quarantined app from a read-only copy at a path that
    /// changes on every launch. Accessibility is granted to a path, so it never
    /// sticks; and Finder, asked to delete the original, sees nothing running
    /// there and does not warn. Both stop the moment the app is moved.
    ///
    /// `SecTranslocateIsTranslocatedURL` would answer this outright, but the
    /// header it lives in is not exposed to Swift. The path is just as sure:
    /// a translocated bundle is always mounted under `/AppTranslocation/`.
    private static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    private static func warnAboutTranslocation() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move LidLock to your Applications folder"
        alert.informativeText =
            "macOS is running LidLock from a temporary copy, because it was opened straight "
            + "out of the folder it was downloaded to. From there it cannot hold on to the "
            + "Accessibility permission it needs to block the keyboard — the copy is thrown "
            + "away and remade on every launch.\n\n"
            + "Quit, drag LidLock into Applications, and open it from there."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Actions


    @objc private func lockNow() {
        do {
            try LockController.shared.lock()
        } catch {
            present(error: error)
        }
    }

    @objc private func toggleCatGuard() {
        let wanted = !Preferences.catGuardEnabled
        if wanted && !EventTap.isPermitted {
            EventTap.requestPermission()
            present(error: LockController.LockError.noAccessibility)
            return
        }
        Preferences.catGuardEnabled = wanted
        CatGuard.shared.refresh()
    }

    private func catDetected() {
        guard !LockController.shared.isLocked else { return }
        // A cat lock has no PIN requirement, so the only failure left is one the
        // user cannot act on right now — stay quiet and keep watching.
        try? LockController.shared.lock(reason: .cat)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 780),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "LidLock Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKey()
    }

    @objc private func quit() {
        guard !LockController.shared.isLocked else { return }
        NSApp.terminate(nil)
    }

    private func present(error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.informativeText = (error as? LocalizedError)?.recoverySuggestion ?? ""
        alert.addButton(withTitle: "OK")
        if case LockController.LockError.noPin = error {
            alert.addButton(withTitle: "Open Settings…")
            if alert.runModal() == .alertSecondButtonReturn { showSettings() }
            return
        }
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: AppDelegate.catGuardTag)?.state = CatGuard.shared.isWatching ? .on : .off

        // Drawn beside the item purely as a reminder — the hotkey itself is
        // registered globally and fires whether or not this menu is open.
        let lock = menu.item(withTag: AppDelegate.lockTag)
        if let shortcut = Preferences.lockShortcut {
            lock?.keyEquivalent = shortcut.label.lowercased()
            lock?.keyEquivalentModifierMask = shortcut.flags
        } else {
            lock?.keyEquivalent = ""
            lock?.keyEquivalentModifierMask = []
        }
    }
}
