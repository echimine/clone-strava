import Foundation
import Testing

/// The app carries the Nervo brand wherever iOS shows it (ADR-032 §1).
/// The unit tests run hosted in the app, so `Bundle.main` is the app's bundle.
struct BrandingTests {
    @Test func theHomeScreenNamesTheAppNervo() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Nervo")
    }

    @Test(arguments: [
        "NSLocationWhenInUseUsageDescription",
        "NSMotionUsageDescription",
        "NSLocalNetworkUsageDescription",
    ])
    func permissionPromptsSpeakAsNervo(key: String) throws {
        let text = try #require(Bundle.main.object(forInfoDictionaryKey: key) as? String)
        #expect(text.hasPrefix("Nervo "))
    }
}
