import Testing
import SwiftUI
@testable import Sage

@Suite("ScoreTier band→color mapping")
struct ScoreTierColorTests {

    @Test func cutsMatchLiveRuleset() {
        let cuts = ScoreTier.cuts
        let bands = RulesetV4.bundled.bands
        #expect(cuts.excellent == bands.excellent)
        #expect(cuts.good == bands.good)
        #expect(cuts.ok == bands.ok)
        #expect(cuts.excellent == 75)
        #expect(cuts.good == 55)
        #expect(cuts.ok == 35)
    }

    @Test func bandColorTokensAreUniqueAndMapped() {
        // Excellent = deep green; Good = light green; OK = amber; Bad = red.
        #expect(ScoreBandColor.excellent == "1F8A5B")
        #expect(ScoreBandColor.good == "3FA870")
        #expect(ScoreBandColor.ok == "B0832A")
        #expect(ScoreBandColor.bad == "C9442B")

        #expect(ScoreBandColor.good != ScoreBandColor.excellent)
        #expect(ScoreBandColor.ok != ScoreBandColor.good)
        #expect(ScoreBandColor.ok != ScoreBandColor.excellent)

        #expect(ScoreTier.excellent.fg == Color(hex: ScoreBandColor.excellent))
        #expect(ScoreTier.good.fg == Color(hex: ScoreBandColor.good))
        #expect(ScoreTier.poor.fg == Color(hex: ScoreBandColor.ok))
        #expect(ScoreTier.bad.fg == Color(hex: ScoreBandColor.bad))
    }

    @Test func scoreColorFollowsBands() {
        #expect(scoreColor(100) == ScoreTier.excellent.fg)
        #expect(scoreColor(75) == ScoreTier.excellent.fg)
        #expect(scoreColor(74) == ScoreTier.good.fg)
        #expect(scoreColor(55) == ScoreTier.good.fg)
        #expect(scoreColor(54) == ScoreTier.poor.fg)
        #expect(scoreColor(35) == ScoreTier.poor.fg)
        #expect(scoreColor(34) == ScoreTier.bad.fg)
        #expect(scoreColor(0) == ScoreTier.bad.fg)
    }

    @Test func scoreColorMatchesScoreTierFg() {
        for s in [10, 34, 35, 54, 55, 74, 75, 90] {
            #expect(scoreColor(s) == scoreTier(s).fg)
        }
    }

    @Test func lightGreenIsDistinctFromDeepGreenAtRingSize() {
        // Good must be unmistakably greener-family than OK amber, and not
        // identical to Excellent — CompactScoreRing uses .mid at ~20–52pt.
        #expect(ScoreTier.good.mid == Color(hex: ScoreBandColor.goodMid))
        #expect(ScoreBandColor.goodMid != ScoreBandColor.excellentMid)
        #expect(ScoreBandColor.goodMid != ScoreBandColor.okMid)
    }
}
