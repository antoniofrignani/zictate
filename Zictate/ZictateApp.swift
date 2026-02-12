//
//  ZictateApp.swift
//  Zictate
//
//  Created by Antonio Frignani on 12/02/26.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct ZictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let sharedModelContainer: ModelContainer
    @StateObject private var appState: AppState

    init() {
        let schema = Schema([
            Item.self,
            AppSettings.self,
            InstalledModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            _appState = StateObject(wrappedValue: AppState(modelContainer: container))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label("Zictate", systemImage: appState.isDictating ? "record.circle.fill" : "record.circle")
                .symbolRenderingMode(.multicolor)
        }

        WindowGroup("Settings", id: "settings") {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 860, height: 620)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installWindowObservers()
        updateActivationPolicyForSettingsVisibility()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installWindowObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateActivationPolicyForSettingsVisibility()
            }
        }
    }

    private func updateActivationPolicyForSettingsVisibility() {
        let hasVisibleSettingsWindow = NSApp.windows.contains { window in
            window.isVisible && window.title.localizedCaseInsensitiveContains("settings")
        }

        if hasVisibleSettingsWindow {
            if NSApp.activationPolicy() != .regular {
                _ = NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
        } else if NSApp.activationPolicy() != .accessory {
            _ = NSApp.setActivationPolicy(.accessory)
        }
    }
}
