import Foundation

nonisolated enum CloudKitSyncConstants {
    static let appPrefix = "com.vivy.vvterm"
    // VVTerm-iOS/VVTerm.entitlements names the container after the bundle ID.
    static let cloudKitContainerIdentifier = "iCloud.\(Bundle.main.bundleIdentifier ?? "")"
    static let recordZoneName = "VVTermZone"
    static let databaseSubscriptionID = "database-changes"

    static let syncEnabledKey = "iCloudSyncEnabled"
    static let pendingCloudKitSyncQueueStorageKey = "\(appPrefix).pendingCloudKitSyncQueue"

    static func changeTokenKey(for zoneName: String = recordZoneName) -> String {
        "\(appPrefix).cloudkit.\(zoneName).token"
    }

    static func zoneReadyKey(for zoneName: String = recordZoneName) -> String {
        "\(appPrefix).cloudkit.\(zoneName).ready"
    }
}
