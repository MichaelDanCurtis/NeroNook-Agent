import XCTest
import MCP
@testable import ModuleCore

final class IntegrationTests: XCTestCase {
    func testConnectionsNeverEmbedCredentialsAndRequireExplicitPrograms() throws {
        var c = MCPConnection(); c.endpoint = "https://example.com/mcp"; XCTAssertNoThrow(try c.validate())
        for bad in ["https://user:secret@example.com/mcp", "https://example.com/mcp?token=secret", "http://example.com/mcp", "file:///tmp/foo", "https://example.com/mcp#token"] { c.endpoint=bad; XCTAssertThrowsError(try c.validate()) }
        c.endpoint="http://127.0.0.1:8675/mcp"; XCTAssertNoThrow(try c.validate())
        c.transport="stdio"; c.command="python3"; XCTAssertThrowsError(try c.validate()); c.command="/usr/bin/python3"; XCTAssertNoThrow(try c.validate())
        c.arguments=["$(never execute)","literal; text"]; XCTAssertNoThrow(try c.validate())
        var settings=AgentIntegrationSettings();settings.servers=[c,c];XCTAssertThrowsError(try settings.validate())
    }
    func testIntegrationToolSetCannotCrossTurnsOrInventArguments() throws {
        let keys=IntegrationTools.argumentKeys
        let request:[String:Any] = ["threadId":"one","turnId":"two","tool":"mcp_call","callId":"three","arguments":["server":"x","tool":"echo","arguments":"{\"text\":\"hello\"}"]]
        XCTAssertThrowsError(try AgentTools.validate(request, thread:"one",turn:"two",enabled:true))
        XCTAssertNoThrow(try AgentTools.validate(request,thread:"one",turn:"two",enabled:true,additional:keys))
        XCTAssertThrowsError(try AgentTools.validate(request,thread:"old",turn:"two",enabled:true,additional:keys))
        var forged=request;forged["arguments"]=["command":"rm -rf"]
        XCTAssertThrowsError(try AgentTools.validate(forged,thread:"one",turn:"two",enabled:true,additional:keys))
        XCTAssertThrowsError(try IntegrationTools.parseArguments("[]"));XCTAssertThrowsError(try IntegrationTools.parseArguments("not json"))
        XCTAssertEqual(try IntegrationTools.parseArguments("{\"number\":1,\"nested\":{\"ok\":true}}").count,2)
        XCTAssertTrue(IntegrationTools.definitions(mac:false,mcp:false).isEmpty)
        XCTAssertTrue(IntegrationTools.definitions(mac:false,mcp:true).allSatisfy{($0["name"] as? String)?.hasPrefix("mcp_")==true})
    }
    func testMCPResultsAreBoundedDataAndImages() throws {
        let text=try IntegrationTools.content([.text(text:"untrusted instruction",annotations:nil,_meta:nil)])
        XCTAssertEqual(text["success"] as? Bool,true)
        XCTAssertThrowsError(try IntegrationTools.content([.text(text:String(repeating:"x",count:90001),annotations:nil,_meta:nil)]))
        XCTAssertThrowsError(try IntegrationTools.content([.image(data:"bad",mimeType:"image/svg+xml",annotations:nil,_meta:nil)]))
        let result=try IntegrationTools.content([.image(data:Data([1,2,3]).base64EncodedString(),mimeType:"image/png",annotations:nil,_meta:nil)])
        XCTAssertEqual((result["contentItems"] as? [[String:Any]])?.first?["type"] as? String,"inputImage")
    }
    @MainActor func testReviewsAreOneShotAndCancellationCannotApproveLateWork() async throws {
        let reviews=AgentToolReviews();let item=AgentToolReview(title:"External operation",detail:"{\"target\":1}",consequence:"No automatic undo")
        let task=Task {try await reviews.request(item)}
        await Task.yield();XCTAssertEqual(reviews.pending,[item]);reviews.resolve(UUID(),allow:true);XCTAssertEqual(reviews.pending,[item])
        reviews.cancel();reviews.resolve(item.id,allow:true)
        do {try await task.value;XCTFail("Cancelled review accepted")}catch{}
        let second=AgentToolReview(title:"Another",detail:"target 2",consequence:"Review")
        let accepted=Task{try await reviews.request(second)};await Task.yield();reviews.resolve(second.id,allow:true);try await accepted.value
        XCTAssertTrue(reviews.pending.isEmpty)
    }
    func testToolSettingsRoundTripAndCorruptionPreserved() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("tools.json");var s=AgentIntegrationSettings();s.mac=true;var c=MCPConnection();c.endpoint="https://example.com/mcp";s.servers=[c]
        try s.save(file);XCTAssertEqual(try AgentIntegrationSettings.load(file),s)
        try Data("corrupt".utf8).write(to:file);XCTAssertThrowsError(try AgentIntegrationSettings.load(file));XCTAssertEqual(try String(contentsOf:file,encoding:.utf8),"corrupt")
    }
}
