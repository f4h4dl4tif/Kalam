import SwiftUI
import AppKit
import Carbon
import LocalAuthentication
import UserNotifications

// MARK: - Lock

/// Locks the window behind Touch ID or the Mac password.
final class LockManager: ObservableObject {
    static let shared = LockManager()
    @Published var isLocked: Bool
    private var resignedAt: Date?

    var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.lockEnabled) }
    var afterMinutes: Int { UserDefaults.standard.integer(forKey: Pref.lockAfter) }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Pref.lockEnabled)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resignedAt = Date()
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.enabled, let since = self.resignedAt else { return }
            if Date().timeIntervalSince(since) >= Double(self.afterMinutes * 60) { self.lock() }
            self.resignedAt = nil
        }
    }

    func lock() {
        guard enabled else { return }
        Store.shared.saveNow()
        isLocked = true
    }

    func unlock() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No password or Touch ID available to check against: don't trap the user out of their writing.
            isLocked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock your journal") { ok, _ in
            DispatchQueue.main.async { if ok { self.isLocked = false } }
        }
    }

    static var methodName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .faceID: return "Face ID"
        default: return "your Mac password"
        }
    }
}

struct LockView: View {
    @EnvironmentObject var lock: LockManager
    @AppStorage(Pref.glass) private var glass = false

    var body: some View {
        ThemeReader { palette in
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(palette.tint)
                Text("Kalam is locked").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(palette.ink)
                Button("Unlock with \(LockManager.methodName)") { lock.unlock() }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .glassButton(glass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.bg)
            .onAppear { lock.unlock() }
        }
    }
}

// MARK: - Global shortcut (Control-Option-J)

final class HotKey {
    static let shared = HotKey()
    private var ref: EventHotKeyRef?
    private var installed = false
    var action: (() -> Void)?

    func setEnabled(_ on: Bool) { on ? register() : unregister() }

    private func register() {
        guard ref == nil else { return }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x4B4C4D31), id: 1) // "KLM1"
        RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

// MARK: - Daily reminder

enum Reminders {
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["kalam.daily"])
        guard UserDefaults.standard.bool(forKey: Pref.reminderEnabled) else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let minutes = UserDefaults.standard.integer(forKey: Pref.reminderMinutes)
            let content = UNMutableNotificationContent()
            content.title = "Time to write"
            content.body = "A few lines is enough. Today's page is waiting."
            var comps = DateComponents()
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "kalam.daily", content: content, trigger: trigger))
        }
    }
}

// MARK: - Opening the main window

enum AppActions {
    static var openMain: (() -> Void)?

    static func showToday() {
        NSApp.activate(ignoringOtherApps: true)
        if let open = openMain { open() }
        else { NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        Store.shared.goToday()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--glass-snapshot"), i + 1 < CommandLine.arguments.count {
            GlassSnapshot.run(into: CommandLine.arguments[i + 1])
            return
        }
        #endif
        HotKey.shared.action = { AppActions.showToday() }
        HotKey.shared.setEnabled(UserDefaults.standard.bool(forKey: Pref.hotKey))
        Reminders.reschedule()

        // Debug aid: KALAM_SNAPSHOT=/path.png saves a picture of the main window after launch.
        if let path = ProcessInfo.processInfo.environment["KALAM_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let view = NSApp.windows.first(where: { $0.canBecomeMain })?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Pref.showMenuBar)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppActions.showToday() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
    }
}
