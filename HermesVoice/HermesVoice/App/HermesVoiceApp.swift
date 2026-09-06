//  Application entry point: owns the single AppState and the main window.

import SwiftUI

@main
struct HermesVoiceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 460, minHeight: 640)
                .background(HermesColors.background)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 520, height: 760)
        .commands {
            // A hidden menu item is the simplest way to get a global-ish shortcut
            // without the Accessibility permission an event tap would need.
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Voice") {
                Button("Push to talk") {
                    appState.startListening()
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])

                Button("Send") {
                    Task { await appState.stopListeningAndSend() }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Divider()

                Button("Stop") {
                    appState.cancelCurrentRequest()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Clear conversation") {
                    appState.clearConversation()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
