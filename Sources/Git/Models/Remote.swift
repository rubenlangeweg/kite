import Foundation

/// A git remote with fetch + push URLs. When only one is configured, both
/// fields carry the same value (that's how `git remote -v` reports it).
struct Remote: Equatable {
    let name: String
    let fetchURL: String
    let pushURL: String
}
