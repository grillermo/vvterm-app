import Foundation
import Testing
@testable import VVTerm

struct TerminalAccessoryInputSnapshotTests {
    @Test
    func resolvesConfiguredItemsInOrderAndSkipsDeletedActions() {
        let activeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let active = TerminalAccessoryCustomAction(
            id: activeID,
            title: "Deploy",
            kind: .command,
            commandContent: "deploy",
            updatedAt: .distantPast
        )
        let deleted = TerminalAccessoryCustomAction(
            id: deletedID,
            title: "",
            kind: .command,
            updatedAt: .distantPast,
            deletedAt: .distantPast
        )
        let profile = TerminalAccessoryProfile(
            schemaVersion: TerminalAccessoryProfile.schemaVersion,
            layout: TerminalAccessoryLayout(
                version: 1,
                activeItems: [
                    .system(.escape),
                    .custom(activeID),
                    .custom(deletedID),
                    .system(.tab)
                ],
                updatedAt: .distantPast
            ),
            customActions: [deleted, active],
            updatedAt: .distantPast,
            lastWriterDeviceId: "test"
        )
        let snapshot = TerminalAccessoryInputSnapshot(profile: profile)

        #expect(snapshot.resolvedItems == [
            .system(.escape),
            .custom(active),
            .system(.tab)
        ])
    }

    @Test
    func equalsOnlyWhenResolvedItemsMatch() {
        let initialProfile = TerminalAccessoryProfile.defaultValue(
            lastWriterDeviceId: "first"
        )
        let initial = TerminalAccessoryInputSnapshot(profile: initialProfile)
        let sameItems = TerminalAccessoryInputSnapshot(
            profile: TerminalAccessoryProfile.defaultValue(lastWriterDeviceId: "second")
        )
        var changedProfile = initialProfile
        changedProfile.layout.activeItems = [.system(.enter)]
        let changedItems = TerminalAccessoryInputSnapshot(profile: changedProfile)

        #expect(sameItems == initial)
        #expect(changedItems != initial)
    }
}
