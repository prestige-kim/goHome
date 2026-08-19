import Foundation
import XCTest
@testable import GoHome

final class TrainRouteCalculatorTests: XCTestCase {
    func testLinearRouteCountsOnlyStationsAheadTowardDestination() {
        let network = makeNetwork(routes: [
            LineRoute(id: "main", isCircular: false, stationIDs: ["a", "b", "c", "d"]),
        ])
        let position = makePosition(current: "b", destination: "d", direction: .downOrOuter)

        XCTAssertEqual(
            TrainRouteCalculator.remainingStationCount(
                for: position,
                selectedStationID: "c",
                networks: [network]
            ),
            1
        )
        XCTAssertNil(
            TrainRouteCalculator.remainingStationCount(
                for: position,
                selectedStationID: "a",
                networks: [network]
            )
        )
    }

    func testBranchDestinationPreventsCountingWrongBranch() {
        let network = makeNetwork(routes: [
            LineRoute(id: "left", isCircular: false, stationIDs: ["a", "b", "c"]),
            LineRoute(id: "right", isCircular: false, stationIDs: ["a", "b", "d"]),
        ])
        let position = makePosition(current: "a", destination: "d", direction: .downOrOuter)

        XCTAssertEqual(
            TrainRouteCalculator.remainingStationCount(
                for: position,
                selectedStationID: "b",
                networks: [network]
            ),
            1
        )
        XCTAssertNil(
            TrainRouteCalculator.remainingStationCount(
                for: position,
                selectedStationID: "c",
                networks: [network]
            )
        )
    }

    func testCircularRouteUsesInnerAndOuterDirection() {
        let network = makeNetwork(routes: [
            LineRoute(id: "circle", isCircular: true, stationIDs: ["a", "b", "c", "d"]),
        ])
        let inner = makePosition(current: "d", destination: "c", direction: .upOrInner)
        let outer = makePosition(current: "b", destination: "c", direction: .downOrOuter)

        XCTAssertEqual(
            TrainRouteCalculator.remainingStationCount(
                for: inner,
                selectedStationID: "a",
                networks: [network]
            ),
            1
        )
        XCTAssertEqual(
            TrainRouteCalculator.remainingStationCount(
                for: outer,
                selectedStationID: "a",
                networks: [network]
            ),
            1
        )
    }

    func testBundledRoutesDecodeAndCoverEverySupportedLine() throws {
        let networks = try BundledLineRouteRepository().loadLineRoutes()

        XCTAssertEqual(networks.count, 19)
        XCTAssertEqual(Set(networks.map(\.lineName)).count, 19)
        XCTAssertEqual(networks.flatMap(\.routes).count, 28)
        XCTAssertTrue(networks.allSatisfy { !$0.routes.isEmpty })
    }

    private func makeNetwork(routes: [LineRoute]) -> LineRouteNetwork {
        LineRouteNetwork(lineName: "테스트선", routes: routes)
    }

    private func makePosition(
        current: String,
        destination: String,
        direction: TrainDirection
    ) -> TrainPosition {
        TrainPosition(
            id: "train",
            lineName: "테스트선",
            stationID: current,
            currentStation: current,
            trainNumber: "1",
            direction: direction,
            destinationStationID: destination,
            destination: destination,
            status: .departed,
            serviceType: .regular,
            isLastTrain: false,
            receivedAt: Date(),
            remainingStationCount: nil
        )
    }
}

final class TrainPositionFreshnessTests: XCTestCase {
    func testPositionBecomesStaleAfterTwoMinutes() {
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let position = TrainPosition(
            id: "train",
            lineName: "1호선",
            stationID: "station",
            currentStation: "역",
            trainNumber: "1",
            direction: .upOrInner,
            destinationStationID: "terminal",
            destination: "종착",
            status: .arrived,
            serviceType: .regular,
            isLastTrain: false,
            receivedAt: receivedAt,
            remainingStationCount: 1
        )

        XCTAssertFalse(position.isStale(comparedTo: receivedAt.addingTimeInterval(120)))
        XCTAssertTrue(position.isStale(comparedTo: receivedAt.addingTimeInterval(121)))
    }
}

final class TrainPositionDisplayPolicyTests: XCTestCase {
    func testSelectKeepsNearestThreePerLineAndDirection() {
        let positions = [
            makePosition(number: "4", line: "1호선", direction: .upOrInner, remaining: 4),
            makePosition(number: "1", line: "1호선", direction: .upOrInner, remaining: 1),
            makePosition(number: "2", line: "1호선", direction: .upOrInner, remaining: 2),
            makePosition(number: "3", line: "1호선", direction: .upOrInner, remaining: 3),
            makePosition(number: "5", line: "1호선", direction: .downOrOuter, remaining: 5),
            makePosition(number: "6", line: "2호선", direction: .upOrInner, remaining: 6),
        ]

        let selected = TrainPositionDisplayPolicy.select(from: positions)

        XCTAssertEqual(selected.map(\.trainNumber), ["1", "2", "3", "5", "6"])
    }

    private func makePosition(
        number: String,
        line: String,
        direction: TrainDirection,
        remaining: Int
    ) -> TrainPosition {
        TrainPosition(
            id: number,
            lineName: line,
            stationID: "station-\(number)",
            currentStation: "현재역",
            trainNumber: number,
            direction: direction,
            destinationStationID: "terminal",
            destination: "종착",
            status: .arrived,
            serviceType: .regular,
            isLastTrain: false,
            receivedAt: Date(),
            remainingStationCount: remaining
        )
    }
}
