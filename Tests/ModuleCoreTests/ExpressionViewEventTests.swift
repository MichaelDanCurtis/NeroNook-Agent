import Foundation
import XCTest
import JavaScriptCore
import NookPluginSDK
@testable import ModuleCore

final class ExpressionViewEventTests: XCTestCase {
    func testShippedCheckboxJavaScriptPassesTheActualSDKEventValidator() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Resources/Views/chat/chat.js"), encoding: .utf8)
        let context = try XCTUnwrap(JSContext())
        // Only DOM storage and callback registration are stubbed. Execute the
        // whole shipped script and capture its actual nero.emit payloads; the
        // real SDK validator below, not this bridge stub, admits the event.
        context.evaluateScript("""
        var captured=[];var nodes={};var nextNode=0;
        function node(id){return nodes[id]||(nodes[id]={dataset:{},before:function(){},setAttribute:function(k,v){this[k]=v},addEventListener:function(){},querySelector:function(){return node(id+'summary')}})}
        var document={getElementById:node,createElement:function(){return node('created'+nextNode++)},querySelectorAll:function(){return []},addEventListener:function(){}};
        var nero={onState:function(){},emit:function(name,values){captured.push({name:name,values:values});return Promise.resolve()}};
        """)
        context.evaluateScript(source)
        XCTAssertNil(context.exception, "The full shipped script must initialize")
        context.evaluateScript("document.getElementById('talkExpression').checked=true;document.getElementById('talkExpression').onchange();document.getElementById('talkExpression').checked=false;document.getElementById('talkExpression').onchange();")
        XCTAssertNil(context.exception)
        let encoded = try XCTUnwrap(context.evaluateScript("JSON.stringify(captured)")?.toString())
        struct Emission: Decodable { let name: String; let values: [String: PluginValue] }
        let events = try JSONDecoder().decode([Emission].self, from: Data(encoded.utf8))
        XCTAssertEqual(events.count, 2)
        let view = PluginCustomView(entry: "fixture/index.html", revision: "expression1", events: [AgentTalkViewControl.definition])
        for (index, emission) in events.enumerated() {
            let event = PluginViewEvent(panelID: "conversation", revision: view.revision, name: emission.name, values: emission.values)
            try view.validate(event)
            XCTAssertEqual(event.name, "talk")
            XCTAssertEqual(try AgentTalkViewControl.expression(event.values), index == 0)
            XCTAssertEqual(event.values["value"], .string(index == 0 ? "true" : "false"))
        }
        // Preserve the real-bridge rejection that exposed the original bug.
        let rejected = PluginViewEvent(panelID: "conversation", revision: view.revision, name: "talk", values: ["command": .string("expression"), "enabled": .boolean(true)])
        XCTAssertThrowsError(try view.validate(rejected))
    }
    func testExpressionHandlerRejectsMissingNoncanonicalAndWrongTypedValues() throws {
        for value in [PluginValue.string("TRUE"), .string("1"), .string(" true "), .boolean(true), .number(1)] {
            XCTAssertThrowsError(try AgentTalkViewControl.expression(["command": .string("expression"), "value": value]))
        }
        XCTAssertThrowsError(try AgentTalkViewControl.expression(["command": .string("expression")]))
        XCTAssertThrowsError(try AgentTalkViewControl.expression(["command": .string("wrong"), "value": .string("true")]))
        XCTAssertTrue(try AgentTalkViewControl.expression(["command": .string("expression"), "value": .string("true")]))
        XCTAssertFalse(try AgentTalkViewControl.expression(["command": .string("expression"), "value": .string("false")]))
    }
}
