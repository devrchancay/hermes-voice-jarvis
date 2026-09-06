//  Root view: shows the HUD and presents the connection sheet when unconfigured.

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Text("HermesVoice")
            .font(HermesFonts.mono(20, weight: .light))
            .foregroundStyle(HermesColors.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.background)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 520, height: 760)
}
