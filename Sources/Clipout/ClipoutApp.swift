import AppKit
import SwiftUI

@main
struct ClipoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: AppController.shared)
        } label: {
            MenuBarLabel(anki: AppController.shared.anki)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if CommandLine.arguments.contains("--selftest") {
                Task { await SelfTest.run() }
                return
            }
            AppController.shared.start()
        }
    }
}
