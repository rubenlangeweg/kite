import Foundation
import Testing
@testable import Kite

@Suite("Release packaging")
struct ReleaseBuildTests {
    private static let repoRoot: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // KiteTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root

    @Test("Kite.entitlements disables the app sandbox for personal use")
    func entitlementsSandboxOff() throws {
        let url = Self.repoRoot.appendingPathComponent("Kite.entitlements")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["com.apple.security.app-sandbox"] as? Bool == false)
    }

    @Test("scripts/build_release.sh exists")
    func buildScriptExists() {
        let url = Self.repoRoot.appendingPathComponent("scripts/build_release.sh")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("scripts/build_release.sh is executable")
    func buildScriptExecutable() throws {
        let url = Self.repoRoot.appendingPathComponent("scripts/build_release.sh")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        #expect((perms & 0o100) != 0, "owner must have +x on build_release.sh (current: \(String(perms, radix: 8)))")
    }

    @Test("scripts/smoke_launch.sh exists and is executable")
    func smokeScriptExists() throws {
        let url = Self.repoRoot.appendingPathComponent("scripts/smoke_launch.sh")
        #expect(FileManager.default.fileExists(atPath: url.path))
        let perms = try ((FileManager.default.attributesOfItem(atPath: url.path))[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        #expect((perms & 0o100) != 0)
    }

    @Test("ReleaseMetadata.targetSizeBytes is 20MB")
    func targetSizeIs20MB() {
        #expect(ReleaseMetadata.targetSizeBytes == 20 * 1024 * 1024)
    }
}
