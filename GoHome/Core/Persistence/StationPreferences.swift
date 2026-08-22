import Combine
import Foundation

@MainActor
final class StationPreferences: ObservableObject {
    @Published private(set) var favoriteStationIDs: [String]
    @Published private(set) var recentStationIDs: [String]

    private let defaults: UserDefaults
    private let favoritesKey: String
    private let recentsKey: String
    private let recentLimit: Int

    init(
        defaults: UserDefaults = .standard,
        namespace: String = "gohome.station-preferences",
        recentLimit: Int = 5
    ) {
        self.defaults = defaults
        favoritesKey = "\(namespace).favorites"
        recentsKey = "\(namespace).recents"
        self.recentLimit = max(1, recentLimit)
        favoriteStationIDs = defaults.stringArray(forKey: favoritesKey) ?? []
        recentStationIDs = defaults.stringArray(forKey: recentsKey) ?? []
    }

    func isFavorite(_ station: Station) -> Bool {
        favoriteStationIDs.contains(station.id)
    }

    func toggleFavorite(_ station: Station) {
        if let index = favoriteStationIDs.firstIndex(of: station.id) {
            favoriteStationIDs.remove(at: index)
        } else {
            favoriteStationIDs.insert(station.id, at: 0)
        }
        defaults.set(favoriteStationIDs, forKey: favoritesKey)
    }

    func recordRecent(_ station: Station) {
        recentStationIDs.removeAll { $0 == station.id }
        recentStationIDs.insert(station.id, at: 0)
        recentStationIDs = Array(recentStationIDs.prefix(recentLimit))
        defaults.set(recentStationIDs, forKey: recentsKey)
    }

    func stations(for ids: [String], from stations: [Station]) -> [Station] {
        let byID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
}
