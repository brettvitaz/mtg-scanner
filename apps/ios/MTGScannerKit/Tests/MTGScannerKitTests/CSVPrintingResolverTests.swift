import XCTest
@testable import MTGScannerKit

final class CSVPrintingResolverTests: XCTestCase {
    private let resolver = CSVPrintingResolver()

    func testTitleAndEditionResolveWithoutCollectorNumber() throws {
        let printing = try CSVImportTestFixtures.printing()
        XCTAssertEqual(resolver.resolve(CSVImportTestFixtures.record(), among: [printing]), printing)
    }

    func testMultipleVariantsRequireReviewWithoutNumber() throws {
        let variants = try [CSVImportTestFixtures.printing(), CSVImportTestFixtures.printing(number: "147")]
        XCTAssertNil(resolver.resolve(CSVImportTestFixtures.record(), among: variants))
        XCTAssertEqual(
            resolver.resolve(CSVImportTestFixtures.record(number: "147"), among: variants)?.collectorNumber, "147"
        )
    }

    func testIDDisambiguatesVariants() throws {
        let variants = try [
            CSVImportTestFixtures.printing(), CSVImportTestFixtures.printing(number: "147", identifier: "bolt-147")
        ]
        let result = resolver.resolve(CSVImportTestFixtures.record(identifier: "bolt-147"), among: variants)
        XCTAssertEqual(result?.collectorNumber, "147")
    }

    func testSuppliedNumberAndIDConflictsDoNotFallBack() throws {
        let printing = try CSVImportTestFixtures.printing()
        XCTAssertNil(resolver.resolve(CSVImportTestFixtures.record(number: "999"), among: [printing]))
        XCTAssertNil(resolver.resolve(CSVImportTestFixtures.record(identifier: "wrong"), among: [printing]))
        XCTAssertNil(resolver.resolve(
            CSVImportTestFixtures.record(number: "999", identifier: "bolt-146"), among: [printing]
        ))
    }

    func testStringCollectorNumbersRemainDistinct() throws {
        let variants = try [
            CSVImportTestFixtures.printing(number: "CSP-78"), CSVImportTestFixtures.printing(number: "78a")
        ]
        XCTAssertEqual(
            resolver.resolve(CSVImportTestFixtures.record(number: "csp-78"), among: variants)?.collectorNumber, "CSP-78"
        )
    }

    func testNoMatchAndUnsupportedFinishRequireReview() throws {
        XCTAssertNil(resolver.resolve(CSVImportTestFixtures.record(), among: []))
        XCTAssertNil(resolver.resolve(
            CSVImportTestFixtures.record(foil: true), among: [try CSVImportTestFixtures.printing(finishes: "nonfoil")]
        ))
        XCTAssertNil(resolver.resolve(
            CSVImportTestFixtures.record(), among: [try CSVImportTestFixtures.printing(finishes: "foil")]
        ))
    }

    func testConflictingSetOrEditionRequiresReview() throws {
        let record = CSVImportRecord(
            title: "Lightning Bolt", edition: "Wrong Edition", setCode: "M10", collectorNumber: nil,
            scryfallId: "bolt-146", quantity: 1, foil: false
        )
        XCTAssertNil(resolver.resolve(record, among: [try CSVImportTestFixtures.printing()]))
    }
}
