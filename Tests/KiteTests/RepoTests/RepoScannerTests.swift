import Foundation
import Testing
@testable import Kite

/// Tests for `RepoScanner` — depth-1 FS discovery of work-tree + bare repos.
///
/// All tests create real fixture directories via `GitFixtureHelper`. Real
/// `git init` / `git init --bare` is used rather than fabricating `.git/`
/// directories by hand, so these tests also regression-guard against git
/// future-versions changing the bare layout.
///
/// Fulfills: VAL-REPO-001 (scanner core), VAL-REPO-002 (non-repo excluded),
/// VAL-REPO-005 (missing root does not throw), VAL-REPO-006 (bare detected).
@Suite("RepoScanner")
struct RepoScannerTests {
    @Test("scans a single root with three work-tree repos and two non-repos")
    func scansSimpleRoot() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("alpha"))
        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("beta"))
        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("gamma"))

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-repo"),
            withIntermediateDirectories: true
        )
        try "hello".write(
            to: root.appendingPathComponent("not-a-repo/notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty-dir"),
            withIntermediateDirectories: true
        )

        let results = await RepoScanner.scan(roots: [root])

        #expect(results.count == 3)
        let names = Set(results.map(\.displayName))
        #expect(names == ["alpha", "beta", "gamma"])
        #expect(results.allSatisfy { !$0.isBare })
    }

    @Test("excludes directories without a .git/ entry")
    func ignoresNonRepoDirectories() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("good-repo"))

        let junk = root.appendingPathComponent("junk")
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try "not a repo".write(
            to: junk.appendingPathComponent("readme.md"),
            atomically: true,
            encoding: .utf8
        )

        let results = await RepoScanner.scan(roots: [root])

        #expect(results.count == 1)
        #expect(results.first?.displayName == "good-repo")
    }

    @Test("detects bare repositories")
    func detectsBareRepos() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let bareDir = root.appendingPathComponent("server.git")
        try GitFixtureHelper.exec(["init", "--bare", bareDir.path], cwd: root)

        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("normal"))

        let results = await RepoScanner.scan(roots: [root])

        #expect(results.count == 2)
        let bare = results.first { $0.displayName == "server.git" }
        #expect(bare != nil)
        #expect(bare?.isBare == true)
        let normal = results.first { $0.displayName == "normal" }
        #expect(normal?.isBare == false)
    }

    @Test("missing root is skipped and does not throw")
    func skipsMissingRoot() async {
        let missing = URL(fileURLWithPath: "/nonexistent-kite-\(UUID().uuidString)")
        let results = await RepoScanner.scan(roots: [missing])
        #expect(results.isEmpty)
    }

    @Test("scans multiple roots and groups results by rootPath")
    func handlesMultipleRoots() async throws {
        let rootA = GitFixtureHelper.tempURL()
        let rootB = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            GitFixtureHelper.cleanup(rootA)
            GitFixtureHelper.cleanup(rootB)
        }

        try GitFixtureHelper.cleanRepo(at: rootA.appendingPathComponent("a1"))
        try GitFixtureHelper.cleanRepo(at: rootA.appendingPathComponent("a2"))
        try GitFixtureHelper.cleanRepo(at: rootB.appendingPathComponent("b1"))
        try GitFixtureHelper.cleanRepo(at: rootB.appendingPathComponent("b2"))

        let results = await RepoScanner.scan(roots: [rootA, rootB])

        #expect(results.count == 4)
        let byRoot = Dictionary(grouping: results, by: \.rootPath)
        #expect(byRoot[rootA.standardizedFileURL]?.count == 2)
        #expect(byRoot[rootB.standardizedFileURL]?.count == 2)
        let aNames = Set((byRoot[rootA.standardizedFileURL] ?? []).map(\.displayName))
        let bNames = Set((byRoot[rootB.standardizedFileURL] ?? []).map(\.displayName))
        #expect(aNames == ["a1", "a2"])
        #expect(bNames == ["b1", "b2"])
    }

    @Test("isRepo returns .workTree for a normal repository")
    func isRepoDetectsWorkTree() throws {
        let tmp = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(tmp) }
        try GitFixtureHelper.cleanRepo(at: tmp)

        #expect(RepoScanner.isRepo(tmp) == .workTree)
    }

    @Test("isRepo returns .bare for a bare repository")
    func isRepoDetectsBare() throws {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(parent) }

        let bare = parent.appendingPathComponent("server.git")
        try GitFixtureHelper.exec(["init", "--bare", bare.path], cwd: parent)

        #expect(RepoScanner.isRepo(bare) == .bare)
    }

    @Test("isRepo returns nil for a non-repository directory")
    func isRepoReturnsNilForNonRepo() throws {
        let tmp = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(tmp) }
        try "hi".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        #expect(RepoScanner.isRepo(tmp) == nil)
    }

    @Test("repos within a root are returned in deterministic case-insensitive order")
    func deterministicOrderingWithinRoot() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("charlie"))
        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("Alpha"))
        try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("beta"))

        let results = await RepoScanner.scan(roots: [root])

        #expect(results.map(\.displayName) == ["Alpha", "beta", "charlie"])
    }

    /// Smoke perf test. Target is <200ms at 100 repos on M1+, but asserting
    /// <500ms keeps the test stable on busy CI machines; if this trips, open
    /// a fix feature rather than tightening the bound here.
    @Test("scans 50 repos comfortably within the perf budget")
    func perfUnder200ms() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        for idx in 0 ..< 50 {
            try GitFixtureHelper.cleanRepo(at: root.appendingPathComponent("repo-\(idx)"))
        }

        let start = ContinuousClock.now
        let results = await RepoScanner.scan(roots: [root])
        let elapsed = ContinuousClock.now - start

        #expect(results.count == 50)
        #expect(elapsed < .milliseconds(500), "scan took \(elapsed) — expected <500ms")
    }
}
