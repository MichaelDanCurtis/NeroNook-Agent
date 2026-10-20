import XCTest
@testable import ModuleCore

final class SpokenReplyPolicyTests: XCTestCase {
    let catalog:[String:Any] = ["data":[["model":"test-model","supportedReasoningEfforts":[["reasoningEffort":"low"],["reasoningEffort":"medium"]]]]]
    func testQuickOnlyOverridesAdvertisedEffortForTheExactSelectedModel() {
        XCTAssertEqual(SpokenReplyPolicy.effort(model:"test-model",catalog:catalog,quick:true),"low")
        XCTAssertNil(SpokenReplyPolicy.effort(model:"another-model",catalog:catalog,quick:true))
        XCTAssertNil(SpokenReplyPolicy.effort(model:"test-model",catalog:catalog,quick:false))
        XCTAssertNil(SpokenReplyPolicy.effort(model:"test-model",catalog:[:],quick:true))
        XCTAssertNil(SpokenReplyPolicy.effort(model:"test-model",catalog:["data":[["model":"test-model","supportedReasoningEfforts":[["reasoningEffort":"medium"]]]]],quick:true))
    }
}
