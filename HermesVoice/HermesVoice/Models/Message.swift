//  A single turn in the conversation.

import Foundation

struct Message: Identifiable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    enum MessageRole: String, Codable, Hashable {
        case system
        case user
        case assistant
    }
}
