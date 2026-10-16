import SwiftUI
import Testing
import UIKit
@testable import StravaClone

/// The Nervo orange (ADR-032 §2), read from the launch screen's colour set (§4).
struct ThemeTests {
    /// The accent is sRGB #FC5200 wherever the app draws it, although the colour set stores it
    /// as the launch screen reads it.
    @Test func theAccentIsNervoOrange() {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Theme.accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let components = [red, green, blue].map { $0 * 255 }
        let expected: [CGFloat] = [0xFC, 0x52, 0x00]
        #expect(zip(components, expected).allSatisfy { abs($0 - $1) < 0.5 }, "\(components) ≠ #FC5200")
        #expect(alpha == 1)
    }
}
