import CoreLocation
import Foundation

struct Station: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let apiName: String
    let latitude: Double
    let longitude: Double
    let lineNames: [String]
    let seoulStationIDs: [String: String]
    let subwayIDs: [String: String]

    init(
        id: String,
        name: String,
        apiName: String? = nil,
        latitude: Double,
        longitude: Double,
        lineNames: [String],
        seoulStationIDs: [String: String] = [:],
        subwayIDs: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.apiName = apiName ?? name
        self.latitude = latitude
        self.longitude = longitude
        self.lineNames = lineNames
        self.seoulStationIDs = seoulStationIDs
        self.subwayIDs = subwayIDs
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }
}

struct NearbyStation: Identifiable, Equatable {
    let station: Station
    let distance: CLLocationDistance

    var id: String { station.id }
}

struct NearbyStationResolution: Equatable {
    let candidates: [NearbyStation]
    let isNearestWithinSupportedRange: Bool
}

enum StationDiscovery {
    static func nearbyStations(
        from stations: [Station],
        location: CLLocation,
        limit: Int = 3,
        supportedRange: CLLocationDistance
    ) -> NearbyStationResolution {
        let candidates = stations
            .map { NearbyStation(station: $0, distance: $0.distance(from: location)) }
            .sorted { $0.distance < $1.distance }
            .prefix(max(0, limit))

        let nearby = Array(candidates)
        return NearbyStationResolution(
            candidates: nearby,
            isNearestWithinSupportedRange: nearby.first.map {
                $0.distance <= supportedRange
            } ?? false
        )
    }

    static func search(
        _ stations: [Station],
        query: String,
        limit: Int = 20
    ) -> [Station] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

        return stations
            .compactMap { station -> (station: Station, rank: Int)? in
                let name = normalize(station.name)
                let apiName = normalize(station.apiName)
                let lines = station.lineNames.map(normalize)

                let rank: Int
                if name == normalizedQuery || apiName == normalizedQuery {
                    rank = 0
                } else if name.hasPrefix(normalizedQuery) || apiName.hasPrefix(normalizedQuery) {
                    rank = 1
                } else if lines.contains(normalizedQuery) {
                    rank = 2
                } else if name.contains(normalizedQuery) ||
                            apiName.contains(normalizedQuery) ||
                            lines.contains(where: { $0.contains(normalizedQuery) }) {
                    rank = 3
                } else {
                    return nil
                }

                return (station, rank)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.station.name != rhs.station.name {
                    return lhs.station.name.localizedStandardCompare(rhs.station.name) == .orderedAscending
                }
                let lhsLines = lhs.station.lineNames.joined(separator: " ")
                let rhsLines = rhs.station.lineNames.joined(separator: " ")
                if lhsLines != rhsLines {
                    return lhsLines.localizedStandardCompare(rhsLines) == .orderedAscending
                }
                return lhs.station.id < rhs.station.id
            }
            .prefix(limit)
            .map { $0.station }
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "ko_KR")
        )
        let compact = folded.components(separatedBy: .whitespacesAndNewlines).joined()
        return compact.hasSuffix("역") ? String(compact.dropLast()) : compact
    }
}
