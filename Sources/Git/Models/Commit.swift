import Foundation

/// A single git commit as parsed from `git log --format='%H%x00%P%x00...'`.
///
/// `parents` preserves the parent-SHA array in order (first parent first) so
/// the graph layout can apply first-parent preference. Merge commits have
/// `parents.count >= 2`; octopus merges `>= 3`. Root commits have `parents == []`.
struct Commit: Equatable, Codable {
    let sha: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let authoredAt: Date
    let subject: String
}
