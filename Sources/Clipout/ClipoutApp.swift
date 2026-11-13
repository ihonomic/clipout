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
            if CommandLine.arguments.contains("--repair-audio") {
                Task { await AudioRepair.run() }
                return
            }
            if let i = CommandLine.arguments.firstIndex(of: "--install-voice") {
                let id = CommandLine.arguments.dropFirst(i + 1).first ?? ""
                Task { await PiperDownloads.shared.installFromCommandLine(id) }
                return
            }
            if CommandLine.arguments.contains("--convert-audio") {
                Task { await AudioConvert.run() }
                return
            }
            if CommandLine.arguments.contains("--selftest") {
                Task { await SelfTest.run() }
                return
            }
            AppController.shared.start()
        }
    }
}
