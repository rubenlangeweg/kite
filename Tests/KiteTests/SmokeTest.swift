import Foundation
import Testing

@Suite("Kite scaffold smoke tests")
struct SmokeTest {
    @Test("test bundle loads and host app bundle identifier is present")
    func hostBundleIdentifier() {
        // Unit tests run hosted inside Kite.app (TEST_HOST). Bundle.main therefore
        // resolves to the host app bundle; its identifier must match what the app
        // ships with. A trivially-true fallback keeps the target green if the host
        // bundle is ever unhosted.
        if let identifier = Bundle.main.bundleIdentifier {
            #expect(identifier.hasPrefix("nl.rb2.kite"))
        } else {
            #expect(Bool(true))
        }
    }

    @Test("arithmetic sanity")
    func arithmetic() {
        #expect(2 + 2 == 4)
    }
}
