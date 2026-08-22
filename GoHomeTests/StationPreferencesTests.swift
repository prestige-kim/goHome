import XCTest
@testable import GoHome

@MainActor
final class StationPreferencesTests: XCTestCase {
    func testFavoriteTogglePersistsInMostRecentOrder() {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let first = makeStation(id: "first", name: "첫번째")
        let second = makeStation(id: "second", name: "두번째")
        context.preferences.toggleFavorite(first)
        context.preferences.toggleFavorite(second)

        XCTAssertEqual(context.preferences.favoriteStationIDs, ["second", "first"])
        XCTAssertTrue(context.preferences.isFavorite(first))

        let restored = StationPreferences(defaults: context.defaults, namespace: context.namespace)
        XCTAssertEqual(restored.favoriteStationIDs, ["second", "first"])

        restored.toggleFavorite(second)
        XCTAssertEqual(restored.favoriteStationIDs, ["first"])
    }

    func testRecentsDeduplicateAndRespectLimit() {
        let context = makeContext(recentLimit: 3)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let stations = (1...4).map { makeStation(id: "station-\($0)", name: "역\($0)") }
        stations.forEach(context.preferences.recordRecent)
        context.preferences.recordRecent(stations[1])

        XCTAssertEqual(
            context.preferences.recentStationIDs,
            ["station-2", "station-4", "station-3"]
        )
    }

    func testStationsPreservePreferenceOrderAndIgnoreMissingIDs() {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        let first = makeStation(id: "first", name: "첫번째")
        let second = makeStation(id: "second", name: "두번째")
        let result = context.preferences.stations(
            for: ["second", "missing", "first"],
            from: [first, second]
        )

        XCTAssertEqual(result.map(\.id), ["second", "first"])
    }

    private func makeContext(recentLimit: Int = 5) -> (
        preferences: StationPreferences,
        defaults: UserDefaults,
        suiteName: String,
        namespace: String
    ) {
        let suiteName = "StationPreferencesTests.\(UUID().uuidString)"
        let namespace = "test-preferences"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            StationPreferences(defaults: defaults, namespace: namespace, recentLimit: recentLimit),
            defaults,
            suiteName,
            namespace
        )
    }

    private func makeStation(id: String, name: String) -> Station {
        Station(id: id, name: name, latitude: 37.5, longitude: 127.0, lineNames: ["2호선"])
    }
}
