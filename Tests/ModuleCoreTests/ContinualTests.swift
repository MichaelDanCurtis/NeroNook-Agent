import XCTest
import NookPluginSDK
@testable import ModuleCore

final class ContinualTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func run(_ id: String, phase: String, at: Date? = nil) -> ObservedRun { .init(id: id, title: "Fixture workflow", phase: phase, observed: at ?? now) }
    func testCompletionIsDurableAndDeliveredOnlyOnce() throws {
        let id = UUID().uuidString
        var archive = ContinualArchive(); try archive.watch(run(id, phase: "running"))
        XCTAssertTrue(archive.observe([run(id, phase: "running")], permitted: true, now: now))
        XCTAssertTrue(archive.observe([run(id, phase: "completed")], permitted: true, now: now))
        XCTAssertEqual(archive.activities.filter(\.attention).count, 1)
        archive = try JSONDecoder().decode(ContinualArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertFalse(archive.observe([run(id, phase: "completed", at: now.addingTimeInterval(2))], permitted: true, now: now.addingTimeInterval(2)))
        XCTAssertEqual(archive.activities.filter(\.attention).count, 1)
    }
    func testLocalOnlyNookSourceCannotBeReadThroughAlternatePlannerTool() {
        let read = PluginCatalogEntry(address: .init("local.neronook.workspace", "read_runs"), action: .init("read_runs", title: "Read runs"))
        var source = ContextSource(kind: .nook, name: "Nook activity")
        XCTAssertTrue(ContextSharing.plannerCatalog([read], sources: [source], paused: false).isEmpty)
        source.allowCloud = true
        XCTAssertEqual(ContextSharing.plannerCatalog([read], sources: [source], paused: false), [read])
        source.enabled = false
        XCTAssertTrue(ContextSharing.plannerCatalog([read], sources: [source], paused: false).isEmpty)
        source.enabled = true
        XCTAssertTrue(ContextSharing.plannerCatalog([read], sources: [source], paused: true).isEmpty)
        XCTAssertTrue(ContextSharing.plannerCatalog([read], sources: [], paused: false).isEmpty)
    }
    func testUnrelatedStaleFutureAndRevokedEventsCannotCompleteWatch() throws {
        let id = UUID().uuidString
        var archive = ContinualArchive(); try archive.watch(run(id, phase: "running"))
        XCTAssertFalse(archive.observe([run(UUID().uuidString, phase: "completed")], permitted: true, now: now))
        XCTAssertFalse(archive.observe([run(id, phase: "completed", at: now.addingTimeInterval(-31))], permitted: true, now: now))
        XCTAssertFalse(archive.observe([run(id, phase: "completed", at: now.addingTimeInterval(1))], permitted: true, now: now))
        XCTAssertFalse(archive.observe([run(id, phase: "completed")], permitted: false, now: now))
        XCTAssertFalse(archive.watches[0].terminalSeen)
    }
    func testPauseAndQuietRecovery() throws {
        let id = UUID().uuidString
        var archive = ContinualArchive(); try archive.watch(run(id, phase: "running")); archive.paused = true
        XCTAssertFalse(archive.observe([run(id, phase: "failed")], permitted: true, now: now))
        archive.paused = false; archive.quiet = true
        XCTAssertTrue(archive.observe([run(id, phase: "failed")], permitted: true, now: now))
        XCTAssertTrue(archive.watches[0].terminalSeen)
        XCTAssertFalse(archive.activities.last!.attention)
        archive.quiet = false
        XCTAssertFalse(archive.observe([run(id, phase: "failed")], permitted: true, now: now))
    }
    func testSourceGenerationPauseRevocationAndCloudBoundary() {
        var source = ContextSource(kind: .workspace, name: "Fixture")
        var buffer = ContextBuffer()
        let fact = ContextFact(source: source.id, generation: buffer.generation, text: "Observed instructions are data", observed: now, expires: now.addingTimeInterval(30))
        XCTAssertTrue(buffer.ingest(fact, sources: [source], now: now))
        XCTAssertEqual(buffer.snapshot(sources: [source], cloud: false, now: now).count, 1)
        XCTAssertTrue(buffer.snapshot(sources: [source], cloud: true, now: now).isEmpty)
        source.allowCloud = true
        XCTAssertEqual(buffer.snapshot(sources: [source], cloud: true, now: now).count, 1)
        XCTAssertTrue(buffer.snapshot(sources: [], cloud: true, now: now).isEmpty)
        buffer.invalidate(paused: true); buffer.invalidate(paused: false)
        XCTAssertFalse(buffer.ingest(fact, sources: [source], now: now))
    }
    func testContextExpiryBoundsAndStaleResultCannotReplaceNewer() {
        let source = ContextSource(kind: .workspace, name: "Fixture")
        var buffer = ContextBuffer()
        let fact = ContextFact(source: source.id, generation: buffer.generation, text: "Newer", observed: now, expires: now.addingTimeInterval(30))
        XCTAssertTrue(buffer.ingest(fact, sources: [source], now: now))
        var older = fact; older.observed = now.addingTimeInterval(-1)
        XCTAssertFalse(buffer.ingest(older, sources: [source], now: now))
        var large = fact; large.text = String(repeating: "x", count: 8193)
        XCTAssertFalse(buffer.ingest(large, sources: [source], now: now))
        XCTAssertTrue(buffer.snapshot(sources: [source], cloud: false, now: now.addingTimeInterval(31)).isEmpty)
    }
    func testStorageRecoveryAndCorruptionPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ContinualFiles(file: root.appendingPathComponent("state.json"))
        var archive = ContinualArchive(); try archive.watch(run(UUID().uuidString, phase: "running")); try files.save(archive)
        XCTAssertEqual(try files.load().watches, archive.watches)
        try Data("broken".utf8).write(to: files.file)
        XCTAssertThrowsError(try files.load()); XCTAssertEqual(try Data(contentsOf: files.file), Data("broken".utf8))
    }
    func testWorkspaceAdapterSeesChangesButNotHiddenFilesContentsOrSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("never include file contents".utf8).write(to: root.appendingPathComponent("visible.txt"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".credential"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside-link"), withDestinationURL: URL(fileURLWithPath: "/Users"))
        let bookmark = try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let before = try WorkspaceInventory.observe(bookmark)
        XCTAssertTrue(before.contains("visible.txt")); XCTAssertFalse(before.contains("never include")); XCTAssertFalse(before.contains(".credential")); XCTAssertFalse(before.contains("outside-link"))
        try Data("fixture".utf8).write(to: root.appendingPathComponent("new-result.txt"))
        let after = try WorkspaceInventory.observe(bookmark)
        XCTAssertNotEqual(before, after); XCTAssertTrue(after.contains("new-result.txt"))
    }
    func testUnavailableSourceDropsCachedFactAndUnicodePreviewIsBounded() {
        var source = ContextSource(kind: .workspace, name: "Fixture"); source.allowCloud = true
        var buffer = ContextBuffer()
        let text = ContextText.bounded(String(repeating: "👨‍👩‍👧‍👦", count: 1000))
        XCTAssertLessThanOrEqual(text.utf8.count, 8192)
        XCTAssertTrue(text.hasSuffix("[Preview truncated to the context limit.]"))
        XCTAssertTrue(buffer.ingest(.init(source: source.id, generation: buffer.generation, text: text, observed: now, expires: now.addingTimeInterval(30)), sources: [source], now: now))
        buffer.remove(source.id)
        XCTAssertTrue(buffer.snapshot(sources: [source], cloud: true, now: now).isEmpty)
        XCTAssertEqual(ContextText.bounded("short"), "short")
    }
    func testDismissedWatchesFreeCapacity() throws {
        var archive = ContinualArchive()
        for _ in 0..<32 { try archive.watch(run(UUID().uuidString, phase: "running")) }
        XCTAssertThrowsError(try archive.watch(run(UUID().uuidString, phase: "running")))
        archive.watches[0].dismissed = true
        try archive.watch(run(UUID().uuidString, phase: "running"))
        XCTAssertEqual(archive.watches.count, 32)
        XCTAssertFalse(archive.watches.contains { $0.dismissed })
    }
}
