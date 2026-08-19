import CoreLocation
import XCTest
@testable import GoHome

final class StationDistanceTests: XCTestCase {
    func testDistanceIsZeroForSameCoordinate() {
        let station = Station(
            id: "test",
            name: "테스트",
            latitude: 37.5,
            longitude: 127.0,
            lineNames: ["테스트선"]
        )
        let location = CLLocation(latitude: 37.5, longitude: 127.0)

        XCTAssertEqual(station.distance(from: location), 0, accuracy: 0.01)
    }

    func testNearerStationSortsFirst() {
        let location = CLLocation(latitude: 37.5, longitude: 127.0)
        let near = Station(
            id: "near",
            name: "가까운역",
            latitude: 37.5001,
            longitude: 127.0,
            lineNames: []
        )
        let far = Station(
            id: "far",
            name: "먼역",
            latitude: 37.6,
            longitude: 127.0,
            lineNames: []
        )

        let sorted = [far, near].sorted {
            $0.distance(from: location) < $1.distance(from: location)
        }

        XCTAssertEqual(sorted.first?.id, "near")
    }
}
