import SwiftData
import Foundation

@Model
final class CompetitorApp {
    var trackId: Int64
    var bundleId: String
    var name: String
    var iconURL: String?
    var subtitle: String?
    var addedAt: Date
    var app: AppRecord?

    @Relationship(deleteRule: .cascade)
    var rankingHistory: [CompetitorKeywordRanking] = []

    init(
        trackId: Int64,
        bundleId: String,
        name: String,
        iconURL: String? = nil,
        subtitle: String? = nil
    ) {
        self.trackId = trackId
        self.bundleId = bundleId
        self.name = name
        self.iconURL = iconURL
        self.subtitle = subtitle
        self.addedAt = .now
    }
}

@Model
final class CompetitorKeywordRanking {
    var term: String
    var country: String
    var position: Int?
    var checkedAt: Date
    var competitor: CompetitorApp?

    init(
        term: String,
        country: String,
        position: Int? = nil,
        checkedAt: Date = .now
    ) {
        self.term = term
        self.country = country
        self.position = position
        self.checkedAt = checkedAt
    }
}
