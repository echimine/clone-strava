import Testing
@testable import StravaClone

/// The offering's `layout` metadata (ADR-035 §6): what a RevenueCat adapter will read.
struct PaywallLayoutTests {
    @Test(arguments: [("A", PaywallLayout.a), ("B", .b), ("C", .c)])
    func eachMetadataValueNamesItsVariant(value: String, layout: PaywallLayout) {
        #expect(PaywallLayout(metadata: value) == layout)
    }

    @Test(arguments: [nil, "", "Z", "a"])
    func aMissingOrUnknownValueGivesTheDefaultC(value: String?) {
        #expect(PaywallLayout(metadata: value) == .c)
    }
}
