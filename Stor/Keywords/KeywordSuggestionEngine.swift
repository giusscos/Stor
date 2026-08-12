import Foundation

/// Ranking and seed selection for the Suggest sheet.
///
/// Apple Ads related-keyword calls follow the seed, not the app. A generic tracked
/// term like “offline” returns Instagram / TikTok because those are globally popular,
/// not because they fit a finance listing. Seeds and sort order have to come from the
/// app’s own listing and tracked terms first.
enum KeywordSuggestionEngine {
    static let maxExpansionSeeds = 6
    static let maxSERPSeeds = 3
    static let maxSERPAppsPerSeed = 12
    static let maxSuggestions = 80
    static let maxTermLength = 30

    /// Popularity at or above this with zero listing overlap is treated as a brand spike.
    static let irrelevantBrandPopularity = 88

    struct TrackedSeed: Equatable {
        var term: String
        var popularity: Int?
        var rank: Int?
    }

    struct ListingContext: Equatable {
        var appName: String
        var subtitle: String?
        var keywords: [String]
        var description: String?
        var tracked: [TrackedSeed]
    }

    struct Candidate: Equatable {
        var term: String
        var source: String
        var popularity: Int?
    }

    struct Ranked: Equatable {
        var term: String
        var source: String
        var popularity: Int?
        var relevance: Double
    }

    // MARK: - Tokens

    static func tokens(in text: String, minimumLength: Int = 3) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= minimumLength && !stopwords.contains($0) }
    }

    /// Unigrams and adjacent bigrams from a title/subtitle, plus a short subtitle phrase.
    static func terms(fromAppName name: String, subtitle: String?) -> [String] {
        var terms: [String] = []
        let chunks = [name, subtitle].compactMap { $0 }
        for chunk in chunks {
            let words = tokens(in: chunk)
            terms.append(contentsOf: words)
            if words.count >= 2 {
                for index in 0..<(words.count - 1) {
                    let bigram = "\(words[index]) \(words[index + 1])"
                    if bigram.count <= maxTermLength {
                        terms.append(bigram)
                    }
                }
            }
        }
        if let subtitle {
            let phrase = subtitle
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let wordCount = tokens(in: phrase).count
            if (2...5).contains(wordCount), phrase.count <= maxTermLength, !phrase.isEmpty {
                terms.append(phrase)
            }
        }
        return uniqued(terms)
    }

    static func vocabulary(from context: ListingContext) -> Set<String> {
        var vocab: Set<String> = []
        vocab.formUnion(tokens(in: context.appName))
        if let subtitle = context.subtitle {
            vocab.formUnion(tokens(in: subtitle))
        }
        for keyword in context.keywords {
            vocab.insert(keyword.lowercased())
            vocab.formUnion(tokens(in: keyword))
        }
        if let description = context.description {
            vocab.formUnion(tokens(in: description).prefix(80))
        }
        for seed in context.tracked {
            vocab.insert(seed.term.lowercased())
            vocab.formUnion(tokens(in: seed.term))
        }
        return vocab
    }

    // MARK: - Seeds

    /// Terms worth sending to Apple Ads / related-app search. Generic modifiers are excluded.
    static func expansionSeeds(from context: ListingContext) -> [String] {
        var scored: [(term: String, score: Double)] = []
        var seen = Set<String>()

        func consider(_ raw: String, bonus: Double) {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableTerm(term) else { return }
            guard !isWeakExpansionSeed(term) else { return }
            guard !isLikelyBrandToken(term, context: context) else { return }
            let key = term.lowercased()
            guard seen.insert(key).inserted else { return }
            scored.append((term, seedScore(term, context: context) + bonus))
        }

        for phrase in terms(fromAppName: context.appName, subtitle: context.subtitle) {
            consider(phrase, bonus: phrase.contains(" ") ? 4 : 1)
        }
        for keyword in context.keywords {
            consider(keyword, bonus: 5)
        }
        if let subtitle = context.subtitle {
            consider(subtitle, bonus: 4)
        }
        for seed in context.tracked {
            consider(seed.term, bonus: 1)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
            }
            .prefix(maxExpansionSeeds)
            .map(\.term)
    }

    static func isWeakExpansionSeed(_ term: String) -> Bool {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if weakExpansionSeeds.contains(key) { return true }
        let parts = tokens(in: key, minimumLength: 2)
        if parts.isEmpty { return true }
        return parts.allSatisfy { weakExpansionSeeds.contains($0) || stopwords.contains($0) }
    }

    /// Single token that only appears in the app name — usually the developer/brand, not a query.
    static func isLikelyBrandToken(_ term: String, context: ListingContext) -> Bool {
        let parts = tokens(in: term)
        guard parts.count == 1, let token = parts.first else { return false }
        let nameTokens = Set(tokens(in: context.appName))
        guard nameTokens.contains(token) else { return false }
        var elsewhere = Set<String>()
        if let subtitle = context.subtitle {
            elsewhere.formUnion(tokens(in: subtitle))
        }
        for keyword in context.keywords {
            elsewhere.formUnion(tokens(in: keyword))
        }
        if let description = context.description {
            elsewhere.formUnion(tokens(in: description).prefix(80))
        }
        for seed in context.tracked {
            elsewhere.formUnion(tokens(in: seed.term))
        }
        guard !elsewhere.contains(token) else { return false }
        return looksLikeBrand(token, in: context.appName)
    }

    // MARK: - Rank

    static func relevance(of term: String, vocabulary: Set<String>) -> Double {
        let parts = tokens(in: term, minimumLength: 2).filter { !stopwords.contains($0) }
        if parts.isEmpty { return 0 }
        let matches = parts.filter { token in
            vocabulary.contains(token) || vocabulary.contains(where: { sharesStem($0, token) })
        }
        return Double(matches.count) / Double(parts.count)
    }

    static func rank(_ candidates: [Candidate], context: ListingContext) -> [Ranked] {
        let vocab = vocabulary(from: context)
        var seen = Set<String>()
        var ranked: [Ranked] = []

        for candidate in candidates {
            let term = candidate.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableTerm(term) else { continue }
            let key = term.lowercased()
            guard seen.insert(key).inserted else { continue }
            if isLikelyBrandToken(term, context: context) { continue }
            let fit = relevance(of: term, vocabulary: vocab)
            if shouldDrop(candidate, relevance: fit) { continue }
            ranked.append(
                Ranked(
                    term: term,
                    source: candidate.source,
                    popularity: candidate.popularity,
                    relevance: fit
                )
            )
        }

        ranked.sort { lhs, rhs in
            if lhs.relevance != rhs.relevance { return lhs.relevance > rhs.relevance }
            let lp = lhs.popularity ?? -1
            let rp = rhs.popularity ?? -1
            if lp != rp { return lp > rp }
            return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
        }
        return Array(ranked.prefix(maxSuggestions))
    }

    // MARK: - Private

    private static func seedScore(_ term: String, context: ListingContext) -> Double {
        var score = 0.0
        let key = term.lowercased()
        let parts = tokens(in: term)
        let vocab = vocabulary(from: context)
        let overlap = parts.filter { token in
            vocab.contains(token) || vocab.contains(where: { sharesStem($0, token) })
        }
        score += Double(overlap.count) * 3

        if context.keywords.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
            score += 5
        }
        if tokens(in: context.appName).contains(where: { key.contains($0) }) {
            score += 2
        }
        if let subtitle = context.subtitle, tokens(in: subtitle).contains(where: { key.contains($0) }) {
            score += 2
        }

        if let tracked = context.tracked.first(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) {
            score += 1
            if let popularity = tracked.popularity {
                if (25...85).contains(popularity) {
                    score += 2
                } else if popularity > 85 {
                    score += 0.3
                }
            }
            if let rank = tracked.rank, rank <= 50 {
                score += 2
            }
        }

        if parts.count >= 2 { score += 1.5 }
        if term.count >= 5 { score += 0.5 }
        return score
    }

    private static func shouldDrop(_ candidate: Candidate, relevance: Double) -> Bool {
        if relevance > 0 { return false }
        if candidate.source.localizedCaseInsensitiveContains("competitor") { return false }
        if candidate.source.localizedCaseInsensitiveContains("listing") { return false }
        let popularity = candidate.popularity ?? 0
        return popularity >= irrelevantBrandPopularity
    }

    private static func looksLikeBrand(_ token: String, in appName: String) -> Bool {
        for separator in [" - ", " – ", " — "] {
            if let range = appName.range(of: separator, options: .backwards) {
                let suffix = String(appName[range.upperBound...])
                if tokens(in: suffix) == [token] { return true }
            }
        }
        let words = appName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let original = words.first(where: { $0.lowercased() == token }) else { return false }
        let letters = original.filter(\.isLetter)
        let uppers = letters.filter(\.isUppercase)
        return letters.count >= 3 && uppers.count >= 2 && uppers.count < letters.count
    }

    private static func isUsableTerm(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= maxTermLength else { return false }
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        return compact.count >= 2
    }

    private static func sharesStem(_ a: String, _ b: String) -> Bool {
        guard a.count >= 4, b.count >= 4 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    private static func uniqued(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for term in terms {
            let key = term.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(term)
        }
        return unique
    }

    static let stopwords: Set<String> = [
        "the", "and", "for", "with", "you", "your", "this", "that", "from", "are",
        "was", "were", "will", "not", "but", "can", "all", "any", "our", "its",
        "a", "an", "of", "to", "in", "on", "at", "by", "or", "as", "is", "be",
        "we", "they", "them", "their", "more", "most", "than", "then", "also",
        "just", "into", "over", "after", "before", "about", "have", "has", "had",
        "been", "being", "do", "does", "did", "using", "use", "used", "get",
        "got", "make", "made", "how", "what", "when", "who", "why", "which"
    ]

    /// Fine as tracked keywords; terrible as Apple Ads expansion seeds.
    static let weakExpansionSeeds: Set<String> = [
        "app", "apps", "application", "apple", "ios", "iphone", "ipad", "mac",
        "macos", "mobile", "free", "best", "new", "pro", "plus", "lite", "premium",
        "offline", "online", "download", "store", "search", "game", "games"
    ]
}
