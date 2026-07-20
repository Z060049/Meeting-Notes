import AppKit
import MeetingNotesCore
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let controller: MeetingNotesController

    init(controller: MeetingNotesController) {
        self.controller = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to MeetingNotes"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)

        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(
                controller: controller,
                onFinish: { [weak self] in
                    self?.close()
                },
                onRestart: {
                    AppRelauncher.relaunch()
                }
            )
        )
    }

    func windowWillClose(_ notification: Notification) {
        // Avoid leaving accessory-app focus chrome after the only visible window closes.
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0 !== notification.object as? NSWindow }
            if !hasVisibleWindow {
                NSApp.deactivate()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        controller.refreshPermissionStatus()
        guard let window else {
            PersistentDiagnosticLog.shared.log(
                "Could not present onboarding because its window is unavailable.",
                level: .error
            )
            return
        }

        showWindow(nil)
        bringToFront(window)
        PersistentDiagnosticLog.shared.log(
            "Onboarding window presented after launch (visible=\(window.isVisible), key=\(window.isKeyWindow))."
        )

        // An LSUIElement app relaunched by a helper may initially be classified
        // as background-only. Repeat activation after AppKit and Control Center
        // finish restoring the menu-bar scene.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let window = self.window, window.isVisible else {
                return
            }
            self.bringToFront(window)
            PersistentDiagnosticLog.shared.log(
                "Onboarding window activation retried (visible=\(window.isVisible), key=\(window.isKeyWindow))."
            )
        }
    }

    private func bringToFront(_ window: NSWindow) {
        window.center()
        // orderFrontRegardless helps after permission relaunch when macOS still
        // classifies the LSUIElement process as background-only. Avoid
        // activateIgnoringOtherApps — it leaves a full-screen focus frame.
        window.orderFrontRegardless()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private enum AppRelauncher {
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        PersistentDiagnosticLog.shared.log(
            "Relaunch requested for \(bundleURL.path)."
        )

        // Child Process helpers are killed with this app's process group on
        // terminate, so sleep/open and nohup waiters never reopen the test
        // build. Open a new instance first, then quit the current one.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    PersistentDiagnosticLog.shared.log(
                        "NSWorkspace relaunch failed: \(error.localizedDescription). Falling back to open().",
                        level: .error
                    )
                    NSWorkspace.shared.open(bundleURL)
                } else {
                    PersistentDiagnosticLog.shared.log(
                        "New MeetingNotes instance launched; terminating current process."
                    )
                }
                NSApp.terminate(nil)
            }
        }
    }
}
