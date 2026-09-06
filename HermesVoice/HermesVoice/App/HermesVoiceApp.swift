//  Application entry point: owns the single AppState and the main window.

import SwiftUI

@main
struct HermesVoiceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 500, minHeight: 700)
                .background(HermesColors.background)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 520, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
