import SwiftData
import Foundation

@Model
final class TrackedKeyword {
    var term: String
    var locale: String
    var country: String
    var addedAt: Date
    var popularityScore: Int?
    var popularityLastUpdated: Date?
    var app: AppRecord?

    @Relationship(deleteRule: .cascade)
    var rankingHistory: [KeywordRanking] = []

    init(term: String, locale: String = "en-US", country: String = "US") {
        self.term = term
        self.locale = locale
        self.country = country
        self.addedAt = .now
    }
}

@Model
final class KeywordRanking {
    var checkedAt: Date
    var position: Int?
    var country: String
    var keyword: TrackedKeyword?

    init(checkedAt: Date = .now, position: Int? = nil, country: String = "US") {
        self.checkedAt = checkedAt
        self.position = position
        self.country = country
    }
}
