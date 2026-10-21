import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var pinLength: Int? = PinStore.load()?.length
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var errorMessage: String?
    @State private var autoUnlock = Preferences.autoUnlockMinutes
    @State private var accessibilityGranted = EventTap.isPermitted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var catGuard = Preferences.catGuardEnabled
    @State private var catSensitivity = Preferences.catSensitivity
    @State private var catHiss = Preferences.catHissEnabled

    private let heartbeat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var pinIsValid: Bool {
        newPin.count >= 4 && newPin.count <= 12
            && newPin.allSatisfy(\.isNumber)
            && newPin == confirmPin
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    if let pinLength {
                        Label("\(pinLength)-digit PIN set", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label("No PIN set", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                    }
                }
                SecureField("New PIN", text: $newPin, prompt: Text("4–12 digits"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                SecureField("Confirm", text: $confirmPin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if pinLength != nil {
                        Button("Remove PIN", role: .destructive, action: removePin)
                    }
                    Button("Save PIN", action: savePin)
                        .buttonStyle(.borderedProminent)
                        .disabled(!pinIsValid)
                }
            } header: {
                Text("Unlock PIN")
            } footer: {
                Text("While locked, type the PIN at any time. The dots light up only for digits that actually match, so stray keypresses from your cloth leave them dark and never need clearing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Unlock automatically after", selection: $autoUnlock) {
                    ForEach(Preferences.autoUnlockChoices, id: \.self) { minutes in
                        Text(Preferences.label(forMinutes: minutes)).tag(minutes)
                    }
                }
                .onChange(of: autoUnlock) { _, value in Preferences.autoUnlockMinutes = value }
            } header: {
                Text("Safety net")
            } footer: {
                Text("A way out if you forget the PIN. Holding the power button for ten seconds always force-restarts the Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                // The menu bar toggles this too, so the switch reads its value
                // back from Preferences on every heartbeat. The side effects
                // belong to the setter rather than to `onChange`, or syncing
                // from outside would re-run them — and ask for Accessibility
                // again while the user is looking at something else.
                Toggle("Watch for cats", isOn: Binding(
                    get: { catGuard },
                    set: { value in
                        catGuard = value
                        if value && !EventTap.isPermitted { EventTap.requestPermission() }
                        Preferences.catGuardEnabled = value
                        CatGuard.shared.refresh()
                    }
                ))
                Picker("Trigger", selection: $catSensitivity) {
                    ForEach(Preferences.CatSensitivity.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!catGuard)
                .onChange(of: catSensitivity) { _, value in
                    Preferences.catSensitivity = value
                    CatGuard.shared.refresh()
                }
                Text(catSensitivity.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Hiss when a cat is caught", isOn: $catHiss)
                    .disabled(!catGuard)
                    .onChange(of: catHiss) { _, value in Preferences.catHissEnabled = value }
            } header: {
                Text("Cat guard")
            } footer: {
                Text("Spots a cat walking on the keys from the timing and spacing of the keypresses alone — it never reads what you type, and nothing is recorded. When it fires, the screen locks with the keyboard; type **human** to take back over. No PIN needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Accessibility access") {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        HStack(spacing: 10) {
                            Label("Required", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                            Button("Open Settings…", action: openAccessibilitySettings)
                        }
                    }
                }
                Toggle("Open LidLock at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in setLaunchAtLogin(value) }
            } header: {
                Text("System")
            } footer: {
                Text("Blocking the keyboard requires Accessibility access. Without it LidLock can darken the screen but not stop keystrokes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onReceive(heartbeat) { _ in
            accessibilityGranted = EventTap.isPermitted
            launchAtLogin = SMAppService.mainApp.status == .enabled
            catGuard = Preferences.catGuardEnabled
            // The guard cannot start before Accessibility is granted, so pick it
            // up the moment the user comes back from System Settings.
            if catGuard && !CatGuard.shared.isWatching { CatGuard.shared.refresh() }
        }
    }

    // MARK: - Actions

    private func savePin() {
        do {
            try PinStore.save(pin: newPin)
            pinLength = newPin.count
            newPin = ""
            confirmPin = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePin() {
        PinStore.clear()
        pinLength = nil
        errorMessage = nil
    }

    private func openAccessibilitySettings() {
        EventTap.requestPermission()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
