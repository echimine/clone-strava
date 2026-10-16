import Foundation
import Testing
@testable import StravaClone

/// ADR-032 §5: the celebration plays from 500 m and 2 min, with at least 2 points.
struct CelebrationEligibilityTests {
    @Test func fromFiveHundredMetersTheCelebrationPlays() {
        #expect(!CelebrationEligibility.allows(distance: Distance(meters: 499), elapsed: .seconds(600), pointCount: 300))
        #expect(CelebrationEligibility.allows(distance: Distance(meters: 500), elapsed: .seconds(600), pointCount: 300))
    }

    @Test func fromTwoMinutesTheCelebrationPlays() {
        #expect(!CelebrationEligibility.allows(distance: Distance(meters: 2_000), elapsed: .seconds(119), pointCount: 300))
        #expect(CelebrationEligibility.allows(distance: Distance(meters: 2_000), elapsed: .seconds(120), pointCount: 300))
    }

    @Test func withASinglePointThereIsNoTraceToCelebrate() {
        #expect(!CelebrationEligibility.allows(distance: Distance(meters: 2_000), elapsed: .seconds(600), pointCount: 1))
        #expect(CelebrationEligibility.allows(distance: Distance(meters: 2_000), elapsed: .seconds(600), pointCount: 2))
    }

    /// Separate from the sport's minimum duration, which only gates Save (60 s for a Run).
    @Test func theThresholdsAreTheirOwnConstants() {
        #expect(CelebrationEligibility.minimumDistance == Distance(meters: 500))
        #expect(CelebrationEligibility.minimumDuration == .seconds(120))
    }
}
