//  Root view: shows the HUD and presents the connection sheet when unconfigured.

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showingSettings = false
    @State private var hasCheckedConfiguration = false

    var body: some View {
        JarvisHUD(showingSettings: $showingSettings)
            .sheet(isPresented: $showingSettings) {
                ConnectionSheet()
                    .environment(appState)
            }
            .task {
                guard !hasCheckedConfiguration else { return }
                hasCheckedConfiguration = true
                // First launch: nothing to connect to yet, so ask for the server.
                if appState.needsConfiguration {
                    showingSettings = true
                } else {
                    await appState.connect()
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(AppState(previewing: true))
        .frame(width: 520, height: 760)
}
