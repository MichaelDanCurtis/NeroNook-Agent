import XCTest
@testable import ModuleCore

final class RuntimeVersionTests: XCTestCase {
    func testOnlyExplicitlyVerifiedRuntimeIdentitiesAreAccepted() {
        XCTAssertTrue(AgentRuntime.accepts(userAgent: "neronook_agent/0.162.0 (Mac OS)"))
        XCTAssertTrue(AgentRuntime.accepts(userAgent: "neronook_agent/0.142.5 (fixture)"))
        for value in ["", "neronook_agent/0.163.0 (Mac OS)", "neronook_agent/0.162.0-dev (Mac OS)", "other/0.162.0 (Mac OS)", "neronook_agent/0.162.01 (Mac OS)"] {
            XCTAssertFalse(AgentRuntime.accepts(userAgent: value))
        }
    }
}
