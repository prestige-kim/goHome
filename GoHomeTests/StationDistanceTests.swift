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

    func testNearbyStationResolutionReturnsTopThreeAndSupportedRange() {
        let stations = [
            makeStation(id: "fourth", name: "네번째", latitude: 37.54),
            makeStation(id: "second", name: "두번째", latitude: 37.52),
            makeStation(id: "first", name: "첫번째", latitude: 37.51),
            makeStation(id: "third", name: "세번째", latitude: 37.53),
        ]

        let resolution = StationDiscovery.nearbyStations(
            from: stations,
            location: CLLocation(latitude: 37.50, longitude: 127.0),
            supportedRange: HomeViewModel.supportedRangeMeters
        )

        XCTAssertEqual(resolution.candidates.map(\.station.id), ["first", "second", "third"])
        XCTAssertTrue(resolution.isNearestWithinSupportedRange)
    }

    func testNearbyStationResolutionMarksOutsideSupportedRange() {
        let resolution = StationDiscovery.nearbyStations(
            from: [makeStation(id: "far", name: "먼역", latitude: 37.60)],
            location: CLLocation(latitude: 37.50, longitude: 127.0),
            supportedRange: HomeViewModel.supportedRangeMeters
        )

        XCTAssertFalse(resolution.isNearestWithinSupportedRange)
    }

    func testStationSearchNormalizesStationSuffixAndPreservesSameNameStations() {
        let stations = [
            makeStation(id: "sinchon-2", name: "신촌", lineNames: ["2호선"]),
            makeStation(id: "sinchon-gyeongui", name: "신촌", lineNames: ["경의중앙선"]),
            makeStation(id: "cityhall", name: "시청", lineNames: ["1호선", "2호선"]),
        ]

        let results = StationDiscovery.search(stations, query: " 신촌역 ")

        XCTAssertEqual(Set(results.map(\.id)), Set(["sinchon-2", "sinchon-gyeongui"]))
    }

    func testStationSearchMatchesLineAndPrioritizesExactStationName() {
        let stations = [
            makeStation(id: "gangnam-gu-office", name: "강남구청", lineNames: ["7호선"]),
            makeStation(id: "gangnam", name: "강남", lineNames: ["2호선"]),
            makeStation(id: "cityhall", name: "시청", lineNames: ["2호선"]),
        ]

        XCTAssertEqual(
            StationDiscovery.search(stations, query: "강남").map(\.id),
            ["gangnam", "gangnam-gu-office"]
        )
        XCTAssertEqual(
            Set(StationDiscovery.search(stations, query: "2호선").map(\.id)),
            Set(["gangnam", "cityhall"])
        )
    }

    func testStationSearchReturnsNoMoreThanRequestedLimit() {
        let stations = (0..<25).map {
            makeStation(id: "line-\($0)", name: "테스트\($0)", lineNames: ["테스트선"])
        }

        XCTAssertEqual(StationDiscovery.search(stations, query: "테스트", limit: 20).count, 20)
    }

    func testBundledStationSearchFindsLegacyAPINameAndSameNameStations() throws {
        let stations = try BundledStationRepository().loadStations()
        let renamedResults = StationDiscovery.search(stations, query: "지제")
        let sameNameResults = StationDiscovery.search(stations, query: "신촌역")

        XCTAssertEqual(renamedResults.first?.name, "평택지제")
        XCTAssertEqual(sameNameResults.count, 2)
        XCTAssertEqual(
            Set(sameNameResults.flatMap(\.lineNames)),
            Set(["2호선", "경의중앙선"])
        )
    }

    private func makeStation(
        id: String,
        name: String,
        latitude: Double = 37.5,
        lineNames: [String] = []
    ) -> Station {
        Station(
            id: id,
            name: name,
            latitude: latitude,
            longitude: 127.0,
            lineNames: lineNames
        )
    }
}
