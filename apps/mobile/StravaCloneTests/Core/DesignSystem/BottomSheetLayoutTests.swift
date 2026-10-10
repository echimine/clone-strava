import CoreGraphics
import Testing
@testable import StravaClone

/// Map tab sheet (spec #22): open at 30 % of the screen, fully open by dragging its list up.
struct BottomSheetLayoutTests {
    /// 1,000 pt available, 30 % collapsed, 60 pt left above the open sheet.
    private let layout = BottomSheetLayout(availableHeight: 1_000, collapsedFraction: 0.3, topMargin: 60)

    @Test func theSheetRestsAtThirtyPercentOrNearlyFullHeight() {
        #expect(layout.height(isExpanded: false) == 300)
        #expect(layout.height(isExpanded: true) == 940)
    }

    @Test func theSheetFollowsTheFingerWithoutLeavingItsBounds() {
        // Dragging up (negative translation) grows the sheet.
        #expect(layout.height(isExpanded: false, dragTranslation: -200) == 500)
        #expect(layout.height(isExpanded: false, dragTranslation: -900) == 940)
        #expect(layout.height(isExpanded: false, dragTranslation: 100) == 300)
        #expect(layout.height(isExpanded: true, dragTranslation: 300) == 640)
    }

    @Test func draggingTheListUpOpensTheSheetInFull() {
        #expect(layout.settlesExpanded(wasExpanded: false, predictedTranslation: -400))
    }

    @Test func aSmallNudgeLeavesTheSheetWhereItWas() {
        #expect(!layout.settlesExpanded(wasExpanded: false, predictedTranslation: -100))
        #expect(layout.settlesExpanded(wasExpanded: true, predictedTranslation: 100))
    }

    @Test func draggingDownBringsTheSheetBackToThirtyPercent() {
        #expect(!layout.settlesExpanded(wasExpanded: true, predictedTranslation: 500))
    }
}
