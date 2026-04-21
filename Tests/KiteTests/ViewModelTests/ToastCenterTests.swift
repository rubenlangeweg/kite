import Foundation
import Testing
@testable import Kite

/// Unit tests for `ToastCenter`. Timing-based cases use generous bounds
/// (5.5s for an auto-dismiss configured at 5s, 6s for a "still present"
/// stickiness check) to absorb scheduler jitter without flaking.
///
/// Fulfills: VAL-UI-004 (success + error toast lifecycle), VAL-UI-005
/// (sticky error + detail round-trip).
@Suite("ToastCenter")
@MainActor
struct ToastCenterTests {
    @Test("success toast appears in toasts array")
    func successToastAppears() {
        let center = ToastCenter()
        center.success("hello")
        #expect(center.toasts.count == 1)
        #expect(center.toasts.first?.kind == .success)
        #expect(center.toasts.first?.message == "hello")
    }

    @Test("success toast auto-dismisses after 5s", .timeLimit(.minutes(1)))
    func successToastAutoDismissesAfter5s() async throws {
        let center = ToastCenter()
        center.success("auto-dismiss me")
        #expect(center.toasts.count == 1)
        try await Task.sleep(nanoseconds: 5_500_000_000)
        #expect(center.toasts.isEmpty, "success toast should clear within 5.5s")
    }

    @Test("error toast is sticky after 6s", .timeLimit(.minutes(1)))
    func errorToastIsSticky() async throws {
        let center = ToastCenter()
        center.error("not going anywhere")
        #expect(center.toasts.count == 1)
        try await Task.sleep(nanoseconds: 6_000_000_000)
        #expect(center.toasts.count == 1, "error toast must never auto-dismiss")
        #expect(center.toasts.first?.kind == .error)
    }

    @Test("dismiss removes a specific toast")
    func dismissRemovesToast() {
        let center = ToastCenter()
        center.error("sticky a")
        center.error("sticky b")
        #expect(center.toasts.count == 2)
        let firstID = try? #require(center.toasts.first?.id)
        guard let id = firstID else {
            Issue.record("could not read toast id")
            return
        }
        center.dismiss(id)
        #expect(center.toasts.count == 1)
        #expect(!center.toasts.contains { $0.id == id })
    }

    @Test("success toast cap evicts oldest success when exceeding max visible")
    func maxVisibleCapped() {
        let center = ToastCenter()
        center.success("s1")
        center.success("s2")
        center.success("s3")
        center.success("s4")
        center.success("s5")
        // Cap is 3 visible successes; oldest two (s1, s2) should be evicted.
        let messages = center.toasts.map(\.message)
        #expect(center.toasts.count == 3)
        #expect(!messages.contains("s1"))
        #expect(!messages.contains("s2"))
        #expect(messages.contains("s3"))
        #expect(messages.contains("s4"))
        #expect(messages.contains("s5"))
    }

    @Test("error toasts are not counted against the success cap")
    func errorsNotCountedAgainstSuccessCap() {
        let center = ToastCenter()
        center.error("persistent failure")
        center.success("s1")
        center.success("s2")
        center.success("s3")
        // Cap only evicts successes; the error stays.
        #expect(center.toasts.count == 4)
        #expect(center.toasts.contains { $0.kind == .error })
    }

    @Test("error detail is preserved on the toast value")
    func detailPreservedOnError() throws {
        let center = ToastCenter()
        let blob = """
        fatal: Authentication failed for 'https://example.com/r.git/'
        remote: Invalid username or password.
        """
        center.error("Push failed", detail: blob)
        let toast = try #require(center.toasts.first)
        #expect(toast.detail == blob)
    }
}
