import Foundation

/// Persists how many times each substitution has been observed.
public protocol CorrectionCountStore: AnyObject {
    func count(for sub: Substitution) -> Int
    /// Increments and returns the new count.
    func increment(_ sub: Substitution) -> Int
    func reset(_ sub: Substitution)
}

/// In-memory store (tests / transient use).
public final class InMemoryCorrectionCountStore: CorrectionCountStore {
    private var counts: [String: Int] = [:]
    public init() {}
    private func key(_ s: Substitution) -> String { "\(s.from.lowercased())→\(s.to)" }
    public func count(for sub: Substitution) -> Int { counts[key(sub)] ?? 0 }
    public func increment(_ sub: Substitution) -> Int {
        let n = (counts[key(sub)] ?? 0) + 1
        counts[key(sub)] = n
        return n
    }
    public func reset(_ sub: Substitution) { counts[key(sub)] = nil }
}

/// UserDefaults-backed store for production use.
public final class UserDefaultsCorrectionCountStore: CorrectionCountStore {
    private let defaults: UserDefaults
    private let storageKey = "learning.correctionCounts"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func load() -> [String: Int] {
        defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    }
    private func save(_ dict: [String: Int]) { defaults.set(dict, forKey: storageKey) }
    private func key(_ s: Substitution) -> String { "\(s.from.lowercased())→\(s.to)" }

    public func count(for sub: Substitution) -> Int { load()[key(sub)] ?? 0 }
    public func increment(_ sub: Substitution) -> Int {
        var dict = load()
        let n = (dict[key(sub)] ?? 0) + 1
        dict[key(sub)] = n
        save(dict)
        return n
    }
    public func reset(_ sub: Substitution) {
        var dict = load()
        dict[key(sub)] = nil
        save(dict)
    }
}

/// Deterministic "learning": when the user edits dictated text, diff it and
/// count the substitutions. A substitution that recurs enough becomes a
/// suggested dictionary rule. No model training — just diffs + counting.
public final class CorrectionObserver {
    private let store: CorrectionCountStore
    /// How many times a substitution must recur before we suggest it.
    public let threshold: Int
    /// Corrections with more than this many substitutions are treated as genuine
    /// rewrites (not vocabulary fixes) and ignored.
    public let maxSubstitutionsPerCorrection: Int

    public init(store: CorrectionCountStore, threshold: Int = 2, maxSubstitutionsPerCorrection: Int = 2) {
        self.store = store
        self.threshold = threshold
        self.maxSubstitutionsPerCorrection = maxSubstitutionsPerCorrection
    }

    /// Records a correction and returns substitutions that have just reached the
    /// suggestion threshold (i.e. worth prompting the user to add to their
    /// dictionary).
    @discardableResult
    public func record(injected: String, corrected: String) -> [Substitution] {
        guard injected != corrected else { return [] }
        let subs = TokenDiff.substitutions(from: injected, to: corrected)
        guard !subs.isEmpty, subs.count <= maxSubstitutionsPerCorrection else { return [] }

        var suggestions: [Substitution] = []
        for sub in subs {
            let count = store.increment(sub)
            if count == threshold {
                suggestions.append(sub)
            }
        }
        return suggestions
    }

    /// Called once the user accepts/dismisses a suggestion so it stops recurring.
    public func clear(_ sub: Substitution) { store.reset(sub) }
}
