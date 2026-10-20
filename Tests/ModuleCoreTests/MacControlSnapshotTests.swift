import XCTest
@testable import ModuleCore

final class MacControlSnapshotTests: XCTestCase {
    private let window = MacControlSnapshot.Node(role: "AXWindow", title: "Document")
    func testStableExactControlPassesAndNilValueDoesNotHideChangedMeaning() throws {
        let reviewed = MacControlSnapshot(path: [window, .init(role: "AXButton", identifier: "save", title: "Save")])
        XCTAssertNoThrow(try reviewed.validate(current: reviewed, sameElements: true))
        for changed in [MacControlSnapshot.Node(role: "AXButton", identifier: "save", title: "Delete"), .init(role: "AXButton", identifier: "delete", title: "Save"), .init(role: "AXButton", identifier: "save", title: "Save", description: "Delete selected item")] {
            XCTAssertThrowsError(try reviewed.validate(current: .init(path: [window, changed]), sameElements: true))
        }
    }
    func testMovedReplacedAndChangedAncestorControlsFailClosed() throws {
        let button = MacControlSnapshot.Node(role: "AXButton", title: "Remove")
        let reviewed = MacControlSnapshot(path: [window, .init(role: "AXGroup", identifier: "row-a", title: "File A"), button])
        XCTAssertThrowsError(try reviewed.validate(current: reviewed, sameElements: false), "Equal labels are insufficient when AX elements changed")
        XCTAssertThrowsError(try reviewed.validate(current: .init(path: [window, .init(role: "AXGroup", identifier: "row-b", title: "File B"), button]), sameElements: true))
        XCTAssertThrowsError(try reviewed.validate(current: .init(path: [.init(role: "AXWindow", title: "Other document"), button]), sameElements: true))
    }
    func testFieldValueAndSecurityClassificationArePartOfReviewSnapshot() throws {
        let reviewed = MacControlSnapshot(path: [window, .init(role: "AXTextArea", value: "Original")])
        XCTAssertThrowsError(try reviewed.validate(current: .init(path: [window, .init(role: "AXTextArea", value: "Edited while review was open")]), sameElements: true))
        XCTAssertThrowsError(try reviewed.validate(current: .init(path: [window, .init(role: "AXTextArea", subrole: "AXSecureTextField", value: "Original")]), sameElements: true))
        XCTAssertFalse(String(describing: reviewed).contains("Original"), "Values are digested, not duplicated in review metadata")
    }
}
