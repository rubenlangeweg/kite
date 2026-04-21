import Foundation
import Testing
@testable import Kite

/// Unit tests for `ProgressCenter`. All lifecycle semantics are
/// synchronous on the main actor — no timing dependencies.
///
/// Fulfills: VAL-UI-006 (toolbar progress indicator data source).
@Suite("ProgressCenter")
@MainActor
struct ProgressCenterTests {
    @Test("begin appends an item and returns its id")
    func beginReturnsHandle() throws {
        let center = ProgressCenter()
        let id = center.begin(label: "Fetch origin")
        #expect(center.active.count == 1)
        #expect(center.isActive)
        let first = try #require(center.active.first)
        #expect(first.id == id)
        #expect(first.label == "Fetch origin")
        #expect(first.percent == nil)
    }

    @Test("update adjusts percent for the matching id")
    func updateAdjustsPercent() throws {
        let center = ProgressCenter()
        let id = center.begin(label: "Pull main")
        center.update(id, percent: 50)
        let item = try #require(center.active.first)
        #expect(item.percent == 50)

        // Switching back to nil flips to indeterminate.
        center.update(id, percent: nil)
        let itemNil = try #require(center.active.first)
        #expect(itemNil.percent == nil)
    }

    @Test("end removes the item and flips isActive")
    func endRemovesItem() {
        let center = ProgressCenter()
        let id = center.begin(label: "Push")
        #expect(center.isActive)
        center.end(id)
        #expect(center.active.isEmpty)
        #expect(!center.isActive)
    }

    @Test("multiple concurrent ops track independently")
    func multipleConcurrentOps() {
        let center = ProgressCenter()
        let fetchOrigin = center.begin(label: "Fetch origin")
        let fetchUpstream = center.begin(label: "Fetch upstream")
        let pullMain = center.begin(label: "Pull main")
        #expect(center.active.count == 3)

        center.update(fetchUpstream, percent: 42)
        #expect(center.active.first { $0.id == fetchUpstream }?.percent == 42)
        #expect(center.active.first { $0.id == fetchOrigin }?.percent == nil)
        #expect(center.active.first { $0.id == pullMain }?.percent == nil)

        center.end(fetchOrigin)
        #expect(center.active.count == 2)
        #expect(!center.active.contains { $0.id == fetchOrigin })

        center.end(fetchUpstream)
        center.end(pullMain)
        #expect(center.active.isEmpty)
    }

    @Test("ending an unknown id is a no-op")
    func endUnknownIdIsSafe() {
        let center = ProgressCenter()
        center.end(UUID())
        #expect(center.active.isEmpty)
    }

    @Test("update clamps nothing on its own — caller passes raw value")
    func updateWithZeroAndHundred() throws {
        let center = ProgressCenter()
        let id = center.begin(label: "Resolving")
        center.update(id, percent: 0)
        #expect(try #require(center.active.first).percent == 0)
        center.update(id, percent: 100)
        #expect(try #require(center.active.first).percent == 100)
    }
}
