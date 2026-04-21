import Foundation
import Testing

/// VAL-PKG-004 guard: every Info.plist key and value documented in the
/// mission packaging spec must be present in both the on-disk source
/// (`Info.plist` at the repo root) and the built bundle (`Bundle.main`
/// when the tests run hosted inside `Kite.app`).
///
/// Checking both surfaces catches two distinct failure modes:
///   - A drive-by edit to `project.yml` overriding a key at build time.
///   - A drive-by edit to `Info.plist` itself dropping or renaming a
///     key.
///
/// The host-bundle check mirrors the `SmokeTest.hostBundleIdentifier`
/// pattern already in the suite: if the tests ever run unhosted
/// (`Bundle.main.bundleIdentifier` absent), the host-bundle assertions
/// degrade to passes rather than false negatives.
///
/// Fulfills: VAL-PKG-004.
@Suite("Info.plist required keys (VAL-PKG-004)")
struct InfoPlistTests {
    /// Required keys and exact values. `NSHighResolutionCapable` is a
    /// boolean in XML; plist decoding surfaces it as `true` (or 1 for
    /// some toolchains), so we check via `Bool`/`NSNumber`.
    ///
    /// Values match the spec in
    /// `.factory/missions/kite-v1/library/mac-app-packaging.md` §6 and
    /// `features.json` M8-app-icon-and-plist.
    /// PNG magic header — 8 bytes identifying a valid PNG file.
    /// Values match RFC 2083 §3.1.
    private static let pngMagic: [UInt8] = [
        0x89, 0x50, 0x4e, 0x47,
        0x0d, 0x0a, 0x1a, 0x0a
    ]

    private static let requiredStringKeys: [(key: String, value: String)] = [
        ("CFBundleIdentifier", "nl.rb2.kite"),
        ("CFBundleName", "Kite"),
        ("CFBundleDisplayName", "Kite"),
        ("CFBundleShortVersionString", "0.1.0"),
        ("CFBundleVersion", "1"),
        ("LSApplicationCategoryType", "public.app-category.developer-tools"),
        ("LSMinimumSystemVersion", "15.0"),
        ("CFBundleDevelopmentRegion", "en"),
        ("CFBundlePackageType", "APPL"),
        ("NSHumanReadableCopyright", "© 2026 Ruben Langeweg")
    ]

    // MARK: - Source-file checks

    /// Walk up from this file to the repo root and load the source
    /// `Info.plist` directly.
    private static func sourcePlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiteTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // <repo>/
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw PlistError.malformed
        }
        return plist
    }

    @Test("Source Info.plist has required string keys with expected values")
    func sourcePlistStringKeys() throws {
        let plist = try Self.sourcePlist()
        for (key, expected) in Self.requiredStringKeys {
            let actual = plist[key] as? String
            #expect(
                actual == expected,
                "Source Info.plist key \(key) = \(String(describing: actual)), expected \(expected)"
            )
        }
    }

    @Test("Source Info.plist has NSHighResolutionCapable = true")
    func sourcePlistHighResolutionCapable() throws {
        let plist = try Self.sourcePlist()
        #expect(
            Self.isTrueish(plist["NSHighResolutionCapable"]),
            "Source NSHighResolutionCapable missing or not true"
        )
    }

    // MARK: - Bundle.main checks (hosted)

    @Test("Bundle.main (Kite.app host) exposes required string keys")
    func hostBundleStringKeys() {
        // When the tests run hosted inside Kite.app (`TEST_HOST` in
        // project.yml), `Bundle.main` resolves to Kite.app and its
        // Info.plist is the processed version. Unhosted runs surface no
        // `bundleIdentifier`; skip cleanly in that case — the source
        // check above is the authoritative gate.
        guard Bundle.main.bundleIdentifier?.hasPrefix("nl.rb2.kite") == true else {
            return
        }
        let info = Bundle.main.infoDictionary ?? [:]
        for (key, expected) in Self.requiredStringKeys {
            let actual = info[key] as? String
            #expect(
                actual == expected,
                "Host bundle key \(key) = \(String(describing: actual)), expected \(expected)"
            )
        }
    }

    @Test("Bundle.main (Kite.app host) has NSHighResolutionCapable = true")
    func hostBundleHighResolutionCapable() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("nl.rb2.kite") == true else {
            return
        }
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(
            Self.isTrueish(info["NSHighResolutionCapable"]),
            "Host bundle NSHighResolutionCapable missing or not true"
        )
    }

    /// PropertyListSerialization surfaces `<true/>` as `Bool`, but some
    /// toolchains hand back an `NSNumber` box. Normalise both.
    private static func isTrueish(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    // MARK: - AppIcon asset check (VAL-PKG-003)

    @Test("AppIcon.appiconset contains PNGs for every required slot")
    func appIconAssetHasEveryRequiredSize() throws {
        let iconset = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiteTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // <repo>/
            .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")

        // Every filename listed in Contents.json must exist and be a
        // non-empty PNG. Catches "pristine Contents.json with no PNGs"
        // — the pre-M8 state.
        let contentsURL = iconset.appendingPathComponent("Contents.json")
        let contentsData = try Data(contentsOf: contentsURL)
        let rawContents = try JSONSerialization.jsonObject(with: contentsData)
        guard
            let contents = rawContents as? [String: Any],
            let images = contents["images"] as? [[String: Any]]
        else {
            Issue.record("AppIcon Contents.json malformed")
            return
        }
        #expect(images.count >= 10, "Expected at least 10 icon slots, got \(images.count)")

        for image in images {
            guard let filename = image["filename"] as? String else {
                Issue.record("AppIcon image entry missing filename: \(image)")
                continue
            }
            let pngURL = iconset.appendingPathComponent(filename)
            let exists = FileManager.default.fileExists(atPath: pngURL.path)
            #expect(exists, "Expected icon PNG at \(pngURL.path)")
            if exists {
                let data = try Data(contentsOf: pngURL)
                #expect(
                    data.count > 8,
                    "\(filename) is empty or too small to be a PNG"
                )
                if data.count >= 8 {
                    let header = Array(data.prefix(8))
                    #expect(header == Self.pngMagic, "\(filename) is not a valid PNG (bad magic)")
                }
            }
        }
    }

    private enum PlistError: Error {
        case malformed
    }
}
