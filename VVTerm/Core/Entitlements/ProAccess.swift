import Foundation

/// Feature access for this build.
///
/// VVTerm ships every capability enabled and has no purchase mechanism, so the
/// former Free/Pro split collapses to a single unlocked value. Feature policies
/// still take their access flag as a parameter; this is the one seam that
/// supplies it, so the tier can be reintroduced in one place if that is ever
/// wanted again.
nonisolated enum ProAccess {
    /// Always `true`: builds are installed by the person who made them.
    static let isUnlocked = true
}
