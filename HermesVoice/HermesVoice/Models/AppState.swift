//  Central observable state coordinating networking, speech, and the HUD.

import Foundation

@Observable
final class AppState {
    var orbState: OrbState = .idle
}

enum OrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)
}
