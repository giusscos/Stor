import Foundation

enum SyncCadence: String, CaseIterable, Identifiable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    var help: String {
        switch self {
        case .off: return "Only sync when you click Sync"
        case .daily: return "Pull listing metadata, popularity, and ranks about once a day while Stor is open"
        case .weekly: return "Pull listing metadata, popularity, and ranks about once a week while Stor is open"
        }
    }

    /// Daily uses a 20-hour floor so a morning launch still fires after yesterday evening.
    /// Weekly uses 6 days for the same reason.
    func isDue(lastSyncedAt: Date?, now: Date = .now) -> Bool {
        switch self {
        case .off:
            return false
        case .daily:
            guard let lastSyncedAt else { return true }
            return now.timeIntervalSince(lastSyncedAt) >= 20 * 3600
        case .weekly:
            guard let lastSyncedAt else { return true }
            return now.timeIntervalSince(lastSyncedAt) >= 6 * 24 * 3600
        }
    }
}

extension AppRecord {
    var syncCadence: SyncCadence {
        get { SyncCadence(rawValue: syncCadenceRaw ?? SyncCadence.off.rawValue) ?? .off }
        set { syncCadenceRaw = newValue == .off ? nil : newValue.rawValue }
    }
}

extension MetadataSnapshot {
    /// Whether App Store Connect would still accept a PATCH for this snapshot’s version.
    var isVersionEditable: Bool {
        guard let versionState else { return true }
        return ASCAppStoreVersion.editableStates.contains(versionState)
    }
}
