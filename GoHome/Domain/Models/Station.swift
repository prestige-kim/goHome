import CoreLocation
import Foundation

struct Station: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let lineNames: [String]

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
