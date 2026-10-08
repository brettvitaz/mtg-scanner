import XCTest
@testable import MTGScannerFixtures

final class FeasibilityCorrectionTests: XCTestCase {
    func testCorrectionPromptUsesOnlyCatalogCandidatesAndPreservesEvidence() throws {
        let card = try XCTUnwrap(ProbeOutput.decode(Data(
            #"{"cards":[{"title":"Bolt","edition":"WRONG","collector_number":"1","foil":false,"confidence":0.8}]}"#
                .utf8)).cards.first)
        let template = "{{title}} {{edition}} {{collector_number}} {{foil}} {{reason}}\n{{candidates_table}}"
        let text = ProbeCorrection.prompt(template, card: card, candidates: [
            ["set_name": "Test", "set_code": "TST", "collector_number": "1", "rarity": "common",
             "finishes": "nonfoil"]], reason: "Invalid set")
        XCTAssertTrue(text.contains("Bolt WRONG 1 false Invalid set"))
        XCTAssertTrue(text.contains("| Test | TST | 1 | common | nonfoil |"))
        XCTAssertFalse(text.contains("{{"))
    }

    func testCorrectionMustSelectARealCandidate() throws {
        let card = try XCTUnwrap(ProbeOutput.decode(Data(
            #"{"cards":[{"title":"Bolt","edition":"TST","collector_number":"001","confidence":0.8}]}"#
                .utf8)).cards.first)
        let candidates = [["name": "Bolt", "set_code": "TST", "collector_number": "1"]]
        XCTAssertTrue(ProbeCorrection.matches(card, candidates: candidates))
        XCTAssertFalse(ProbeCorrection.matches(card, candidates: [["name": "Bolt", "set_code": "BAD",
                                                                   "collector_number": "1"]]))
    }

    func testCostEstimateIncludesInputAndOutputTokens() {
        let usage = ProbeUsage(inputTokens: 12, outputTokens: 3)
        XCTAssertEqual(usage.estimatedCost(inputRate: 1, outputRate: 2), 0.000018, accuracy: 0.000000001)
    }
}
