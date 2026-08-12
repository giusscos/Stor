import Foundation

/// One term considered for the 100-character App Store keywords field.
struct KeywordBudgetCandidate: Equatable {
    var term: String
    var opportunity: Int
    var currentlyListed: Bool
}

struct KeywordBudgetPlan: Equatable {
    var current: String
    var proposed: String
    var kept: [String]
    var added: [String]
    var dropped: [String]
    var remaining: Int

    var didChange: Bool { current != proposed }
}

/// Packs tracked keywords into the 100-character ASC `keywords` field.
/// Comma-separated, no spaces after commas (Apple’s convention).
enum KeywordBudget {
    static let limit = MetadataField.keywords.limit

    static func parse(_ raw: String) -> [String] {
        raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func encode(_ terms: [String]) -> String {
        terms.joined(separator: ",")
    }

    static func encodedLength(_ terms: [String]) -> Int {
        encode(terms).count
    }

    static func remaining(in raw: String) -> Int {
        max(0, limit - raw.count)
    }

    /// Greedy pack: highest opportunity first. On a tie, keep currently listed terms.
    static func pack(current: String, candidates: [KeywordBudgetCandidate]) -> KeywordBudgetPlan {
        let currentTerms = parse(current)
        let currentKeys = Set(currentTerms.map { $0.lowercased() })

        var byKey: [String: KeywordBudgetCandidate] = [:]
        for term in currentTerms {
            let key = term.lowercased()
            byKey[key] = KeywordBudgetCandidate(
                term: term,
                opportunity: 0,
                currentlyListed: true
            )
        }
        for candidate in candidates {
            let trimmed = candidate.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if var existing = byKey[key] {
                existing.opportunity = max(existing.opportunity, candidate.opportunity)
                existing.currentlyListed = existing.currentlyListed || candidate.currentlyListed || currentKeys.contains(key)
                byKey[key] = existing
            } else {
                byKey[key] = KeywordBudgetCandidate(
                    term: trimmed,
                    opportunity: candidate.opportunity,
                    currentlyListed: candidate.currentlyListed || currentKeys.contains(key)
                )
            }
        }

        let ranked = byKey.values.sorted { lhs, rhs in
            if lhs.opportunity != rhs.opportunity { return lhs.opportunity > rhs.opportunity }
            if lhs.currentlyListed != rhs.currentlyListed { return lhs.currentlyListed }
            return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
        }

        var packed: [String] = []
        var packedKeys = Set<String>()
        for candidate in ranked {
            let key = candidate.term.lowercased()
            guard packedKeys.insert(key).inserted else { continue }
            var trial = packed
            trial.append(candidate.term)
            guard encodedLength(trial) <= limit else { continue }
            packed = trial
        }

        let packedKeysFinal = Set(packed.map { $0.lowercased() })
        let kept = currentTerms.filter { packedKeysFinal.contains($0.lowercased()) }
        let dropped = currentTerms.filter { !packedKeysFinal.contains($0.lowercased()) }
        let added = packed.filter { !currentKeys.contains($0.lowercased()) }
        let proposed = encode(packed)

        return KeywordBudgetPlan(
            current: encode(currentTerms),
            proposed: proposed,
            kept: kept,
            added: added,
            dropped: dropped,
            remaining: remaining(in: proposed)
        )
    }
}
