import SwiftUI
import SwiftData

@main
struct StorApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            AppRecord.self,
            MetadataSnapshot.self,
            LocalizedMetadata.self,
            TrackedKeyword.self,
            KeywordRanking.self,
            CompetitorApp.self,
            CompetitorKeywordRanking.self,
            ScreenshotTemplate.self
        ])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        SyncScheduler.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 750)
        .commands {
            // Disable File > New since we manage apps via the sidebar
            CommandGroup(replacing: .newItem) {}
            ScreenshotLayerMenu()
        }

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
