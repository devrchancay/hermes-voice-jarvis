//  Smoke tests proving the app target is linkable and the palette matches the spec.

import SwiftUI
import XCTest

@testable import HermesVoice

final class ScaffoldTests: XCTestCase {
    func testPaletteMatchesSpec() throws {
        let cases: [(Color, UInt32)] = [
            (HermesColors.primary, 0x00A8FF),
            (HermesColors.secondary, 0x00F5FF),
            (HermesColors.error, 0xFF6B35),
        ]
        for (color, hex) in cases {
            let components = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
            let expected = (
                r: CGFloat((hex >> 16) & 0xFF) / 255,
                g: CGFloat((hex >> 8) & 0xFF) / 255,
                b: CGFloat(hex & 0xFF) / 255
            )
            XCTAssertEqual(components.redComponent, expected.r, accuracy: 0.001)
            XCTAssertEqual(components.greenComponent, expected.g, accuracy: 0.001)
            XCTAssertEqual(components.blueComponent, expected.b, accuracy: 0.001)
        }
    }

    func testMessageDefaultsAreStable() {
        let message = Message(role: .user, content: "hello")
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "hello")
        XCTAssertEqual(message.role.rawValue, "user")
    }
}
