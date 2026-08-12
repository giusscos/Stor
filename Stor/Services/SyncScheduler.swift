import AppKit
import Foundation
import SwiftData

/// Runs due per-app syncs while Stor is open. macOS does not give a reliable
/// background budget after quit, so this is a Timer-style loop plus wake-from-sleep.
@MainActor
final class SyncScheduler {
    static let shared = SyncScheduler()

    private var container: ModelContainer?
    private var loopTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var running = false

    private init() {}

    func start(container: ModelContainer) {
        self.container = container
        guard loopTask == nil else { return }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.runDueApps()
            }
        }

        loopTask = Task { [weak self] in
            await self?.runDueApps()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                await self?.runDueApps()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func runDueApps() async {
        guard !running else { return }
        guard let container else { return }
        guard (try? KeychainService.shared.load()) != nil else { return }

        running = true
        defer { running = false }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppRecord>()
        guard let apps = try? context.fetch(descriptor) else { return }

        for app in apps where app.syncCadence.isDue(lastSyncedAt: app.lastSyncedAt) {
            await refresh(app: app, context: context)
        }
        try? context.save()
    }

    func refresh(app: AppRecord, context: ModelContext) async {
        guard let credentials = try? KeychainService.shared.load() else {
            app.lastSyncError = "No API credentials found."
            return
        }
        do {
            _ = try await MetadataSyncService.sync(
                app: app,
                versionId: app.preferredVersionId,
                credentials: credentials,
                context: context
            )
            try await ASORefreshService.refreshAll(app: app, context: context)
            app.lastSyncError = nil
        } catch is CancellationError {
            return
        } catch {
            app.lastSyncError = error.localizedDescription
        }
    }
}
