import SwiftUI
import SwiftData

@main
struct StorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            AppRecord.self,
            MetadataSnapshot.self,
            LocalizedMetadata.self,
            TrackedKeyword.self,
            KeywordRanking.self,
            CompetitorApp.self,
            CompetitorKeywordRanking.self,
            ScreenshotTemplate.self
        ])
        .defaultSize(width: 1200, height: 750)
        .commands {
            // Disable File > New since we manage apps via the sidebar
            CommandGroup(replacing: .newItem) {}
            ScreenshotLayerMenu()
        }

        Settings {
            SettingsView()
                .modelContainer(for: [
                    AppRecord.self,
                    MetadataSnapshot.self,
                    LocalizedMetadata.self,
                    TrackedKeyword.self,
                    KeywordRanking.self,
                    CompetitorApp.self,
                    CompetitorKeywordRanking.self,
                    ScreenshotTemplate.self
                ])
        }
    }
}
