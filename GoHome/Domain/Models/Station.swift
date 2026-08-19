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
