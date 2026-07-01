import AppKit
import AutoScribeCore
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AutoScribeController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private var isShowingSilenceAlert = false
    private var isShowingProcessingAlert = false
    private var previousState: AppState = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePopover()
        bindState()
        bindSilencePrompt()
        bindProcessingFailure()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading
        self.statusItem = statusItem
        updateStatusItem(for: controller.state)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit AutoScribe",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 680)
        popover.contentViewController = NSHostingController(rootView: MenuBarRootView(controller: controller))
        self.popover = popover
    }

    private func bindState() {
        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.handleStateTransition(to: state)
                self.updateStatusItem(for: state)
            }
            .store(in: &cancellables)
    }

    private func handleStateTransition(to state: AppState) {
        defer { previousState = state }
        if case .processing = previousState, case .complete = state {
            playCompletionSound()
        }
    }

    private func playCompletionSound() {
        // Gentle chime to signal transcription is done, akin to Cursor's task-complete sound.
        NSSound(named: "Glass")?.play()
    }

    private func bindSilencePrompt() {
        controller.silenceDetected
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    self?.presentSilencePrompt()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor private func presentSilencePrompt() {
        guard controller.state.isRecording, !isShowingSilenceAlert else {
            return
        }
        isShowingSilenceAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Still recording?"
        alert.informativeText = "AutoScribe hasn't detected any audio for 3 minutes. Do you want to stop recording?"
        alert.addButton(withTitle: "Stop Recording")
        alert.addButton(withTitle: "Keep Recording")
        let response = alert.runModal()
        isShowingSilenceAlert = false

        if response == .alertFirstButtonReturn {
            controller.stopRecording()
        } else {
            controller.keepRecordingAfterSilence()
        }
    }

    private func bindProcessingFailure() {
        controller.processingFailed
            .receive(on: RunLoop.main)
            .sink { [weak self] failure in
                MainActor.assumeIsolated {
                    self?.presentProcessingFailure(failure)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor private func presentProcessingFailure(_ failure: ProcessingFailure) {
        guard !isShowingProcessingAlert else {
            return
        }
        isShowingProcessingAlert = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't process this recording"
        alert.informativeText = failure.message
        if failure.savedAudioURL != nil {
            alert.addButton(withTitle: "Open Folder")
        }
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        isShowingProcessingAlert = false

        if response == .alertFirstButtonReturn, let url = failure.savedAudioURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func updateStatusItem(for state: AppState) {
        statusItem?.button?.title = " AutoScribe: \(state.title)"
        statusItem?.button?.image = NSImage(systemSymbolName: state.menuBarSymbolName, accessibilityDescription: state.title)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
