import XCTest
import MCP
@testable import ModuleCore

/// Authored subprocess only: no sockets, accounts, credentials or user files.
final class MCPRequestLifecycleTests: XCTestCase {
    private let fixture = #"""
import json,sys,threading
lock=threading.Lock()
def emit(message):
 with lock: print(json.dumps(message),flush=True)
def reply(identifier,result): emit({'jsonrpc':'2.0','id':identifier,'result':result})
for line in sys.stdin:
 m=json.loads(line);method=m.get('method');p=m.get('params',{})
 if 'id' not in m: continue
 if method=='initialize':r={'protocolVersion':'2025-11-25','capabilities':{'tools':{},'resources':{},'prompts':{}},'serverInfo':{'name':'authored-lifecycle-fixture','version':'1'}}
 elif method=='tools/list':r={'tools':[{'name':'echo','inputSchema':{'type':'object','properties':{}}},{'name':'slow','inputSchema':{'type':'object','properties':{}}},{'name':'exit','inputSchema':{'type':'object','properties':{}}}]}
 elif method=='tools/call':
  if p.get('name')=='exit':sys.exit(0)
  if p.get('name')=='slow':continue
  r={'content':[{'type':'text','text':'authored echo'}]}
 elif method=='resources/read':
  if p.get('uri')=='fixture://slow':continue
  if p.get('uri')=='fixture://late':
   threading.Timer(0.7,reply,args=(m['id'],{'contents':[{'uri':'fixture://late','text':'late result'}]})).start();continue
  r={'contents':[{'uri':p.get('uri'),'text':'authored resource'}]}
 elif method=='resources/list':
  if p.get('cursor')=='slow':continue
  r={'resources':[]}
 elif method=='prompts/list':
  if p.get('cursor')=='slow':continue
  r={'prompts':[]}
 elif method=='prompts/get':
  if p.get('name')=='slow':continue
  r={'messages':[{'role':'user','content':{'type':'text','text':'authored prompt'}}]}
 else:r={}
 reply(m['id'],r)
"""#
    @MainActor private func session(timeout: Duration) async throws -> (AgentMCPSession, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nero-mcp-lifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let script = directory.appendingPathComponent("fixture.py"); try Data(fixture.utf8).write(to: script)
        var configuration = MCPConnection(); configuration.transport = "stdio"; configuration.command = "/usr/bin/python3"; configuration.arguments = [script.path]
        let session = AgentMCPSession(configuration, requestTimeout: timeout)
        do { try await session.connect(); return (session, directory) }
        catch { session.disconnect(); try? FileManager.default.removeItem(at: directory); throw error }
    }
    @MainActor private func waitForOperations(_ count: Int, session: AgentMCPSession) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(3))
        while session.pendingOperationCount < count {
            guard ContinuousClock.now < end else { XCTFail("Requests did not register"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @MainActor func testStopCancelsEveryOperationAndOldDeadlinesCannotRetireReusedSession() async throws {
        let (session, directory) = try await session(timeout: .seconds(1))
        defer { session.disconnect(); try? FileManager.default.removeItem(at: directory) }
        let tasks: [Task<String, Error>] = [
            Task { try await session.resources(cursor: "slow") },
            Task { try await session.read("fixture://slow") },
            Task { try await session.prompts(cursor: "slow") },
            Task { try await session.prompt("slow", arguments: "{}") },
            Task { _ = try await session.call("slow", arguments: "{}"); return "unexpected" }
        ]
        try await waitForOperations(tasks.count, session: session)
        let stopped = ContinuousClock.now; session.cancel()
        for task in tasks { do { _ = try await task.value; XCTFail("Stopped operation succeeded") } catch {} }
        XCTAssertLessThan(stopped.duration(to: .now), .milliseconds(500))
        _ = try await session.call("echo", arguments: "{}")
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(session.tools.count, 3); XCTAssertNotNil(session.capabilities)
        let resource = try await session.read("fixture://normal")
        XCTAssertTrue(resource.contains("authored resource"))
        _ = try await session.call("echo", arguments: "{}")
    }
    @MainActor func testRequestDeadlineIsLocalAndLateResultCannotDisruptNextRequest() async throws {
        let (session, directory) = try await session(timeout: .milliseconds(400))
        defer { session.disconnect(); try? FileManager.default.removeItem(at: directory) }
        do { _ = try await session.read("fixture://late"); XCTFail("Late operation completed") }
        catch { XCTAssertTrue(error.localizedDescription.contains("did not respond in time")) }
        XCTAssertEqual(session.tools.count, 3)
        _ = try await session.call("echo", arguments: "{}")
        try await Task.sleep(for: .milliseconds(500))
        let prompt = try await session.prompt("normal", arguments: "{}")
        XCTAssertTrue(prompt.contains("authored prompt"))
        XCTAssertEqual(session.pendingOperationCount, 0)
    }
    @MainActor func testTaskCancellationAlsoCancelsResourceRequestWithoutDisconnect() async throws {
        let (session, directory) = try await session(timeout: .seconds(1))
        defer { session.disconnect(); try? FileManager.default.removeItem(at: directory) }
        let task = Task { try await session.read("fixture://slow") }
        try await waitForOperations(1, session: session); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled task completed") } catch {}
        XCTAssertEqual(session.pendingOperationCount, 0)
        _ = try await session.call("echo", arguments: "{}")
    }
    @MainActor func testOwnedProcessDeathRetiresSessionAndNotifiesExactlyOnce() async throws {
        let (session, directory) = try await session(timeout: .seconds(2))
        defer { session.disconnect(); try? FileManager.default.removeItem(at: directory) }
        var notices = 0; session.onDisconnect = { notices += 1 }
        do { _ = try await session.call("exit", arguments: "{}"); XCTFail("Exited process returned a result") } catch {}
        XCTAssertEqual(notices, 1); XCTAssertTrue(session.tools.isEmpty); XCTAssertNil(session.capabilities)
        session.disconnect(); XCTAssertEqual(notices, 1)
        let (replacement, replacementDirectory) = try await self.session(timeout: .seconds(2))
        defer { replacement.disconnect(); try? FileManager.default.removeItem(at: replacementDirectory) }
        session.disconnect()
        _ = try await replacement.call("echo", arguments: "{}")
        XCTAssertEqual(replacement.tools.count, 3)
    }
    func testTransportFailureClassificationDoesNotConfuseCancellationOrDeadlineWithConnectionDeath() {
        XCTAssertFalse(AgentMCPSession.isConnectionFailure(CancellationError()))
        XCTAssertFalse(AgentMCPSession.isConnectionFailure(URLError(.timedOut)))
        XCTAssertFalse(AgentMCPSession.isConnectionFailure(MCPError.transportError(URLError(.cancelled))))
        XCTAssertTrue(AgentMCPSession.isConnectionFailure(MCPError.connectionClosed))
        XCTAssertTrue(AgentMCPSession.isConnectionFailure(URLError(.networkConnectionLost)))
        XCTAssertTrue(AgentMCPSession.isConnectionFailure(MCPError.internalError("Session expired")))
        XCTAssertFalse(AgentMCPSession.isConnectionFailure(MCPError.invalidParams("Authored bad input")))
    }
}
