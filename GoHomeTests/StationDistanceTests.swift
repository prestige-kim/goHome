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

    func testDistantStationIsOutsideSupportedRange() {
        let station = Station(
            id: "distant",
            name: "먼역",
            latitude: 37.6,
            longitude: 127.0,
            lineNames: []
        )
        let location = CLLocation(latitude: 37.5, longitude: 127.0)

        XCTAssertGreaterThan(
            station.distance(from: location),
            HomeViewModel.supportedRangeMeters
        )
    }

    func testBundledStationDataIsCompleteAndDecodes() throws {
        let stations = try BundledStationRepository().loadStations()

        XCTAssertGreaterThanOrEqual(stations.count, 550)
        XCTAssertEqual(Set(stations.map(\.id)).count, stations.count)
        XCTAssertEqual(stations.flatMap(\.lineNames).count, 696)
        XCTAssertTrue(stations.allSatisfy { (33...39).contains($0.latitude) })
        XCTAssertTrue(stations.allSatisfy { (124...132).contains($0.longitude) })
    }

    func testRenamedStationUsesLegacyAPIName() throws {
        let stations = try BundledStationRepository().loadStations()
        let station = try XCTUnwrap(stations.first { $0.name == "평택지제" })

        XCTAssertEqual(station.apiName, "지제")
        XCTAssertEqual(station.lineNames, ["1호선"])
    }

    func testSameNameNonTransferStationsRemainSeparate() throws {
        let stations = try BundledStationRepository().loadStations()
        let yangpyeong = stations.filter { $0.name == "양평" }
        let sinchon = stations.filter { $0.apiName.hasPrefix("신촌") }

        XCTAssertEqual(yangpyeong.count, 2)
        XCTAssertEqual(sinchon.count, 2)
        XCTAssertEqual(Set(sinchon.flatMap(\.lineNames)), Set(["2호선", "경의중앙선"]))
    }
}
