import XCTest
@testable import ModuleCore

final class AgentModelChoiceTests: XCTestCase {
    func testOnlyVisibleTextModelsAreOfferedAndRuntimeModelIsRequestValue() throws {
        let values: [[String: Any]] = [
            ["id":"ui-id", "model":"actual-model", "displayName":"A", "isDefault":true],
            ["model":"hidden", "hidden":true], ["model":"images", "inputModalities":["image"]],
            ["model":"actual-model"], ["model":"bad\nvalue"], ["model":String(repeating:"x",count:161)],
            ["model":"text", "inputModalities":["text"]]]
        let choices = try AgentModelChoice.parse(["data":values])
        XCTAssertEqual(choices.map(\.id), ["actual-model","text"])
        XCTAssertEqual(choices.first?.name, "A"); XCTAssertEqual(choices.first?.isDefault, true)
    }
    func testModelPagesAreBoundedAndKeepCurrentChoice() throws {
        let choices = try AgentModelChoice.parse(["data":(0..<90).map{["model":"model-\($0)"]}])
        XCTAssertEqual(AgentModelChoice.page(choices,selected:"model-80",index:0).count,13)
        XCTAssertEqual(AgentModelChoice.page(choices,selected:"model-80",index:0).first?.id,"model-80")
        XCTAssertEqual(AgentModelChoice.page(choices,selected:"",index:999).last?.id,"model-89")
        XCTAssertEqual(AgentModelChoice.page(choices,selected:"",index:-1).first?.id,"model-0")
    }
    func testUnavailableSavedChoiceDoesNotSilentlyFallBack() throws {
        let choices = try AgentModelChoice.parse(["data":[["model":"offered"]]])
        XCTAssertNoThrow(try AgentModelChoice.validate("", choices:choices))
        XCTAssertNoThrow(try AgentModelChoice.validate("offered", choices:choices))
        XCTAssertThrowsError(try AgentModelChoice.validate("old", choices:choices))
        XCTAssertThrowsError(try AgentModelChoice.parse([:]))
        XCTAssertThrowsError(try AgentModelChoice.parse(["data":Array(repeating:["model":"a"],count:257)]))
    }
}
