import Foundation

enum TrainPositionStatus: String, Equatable, Sendable {
    case approaching = "진입"
    case arrived = "도착"
    case departed = "출발"
    case departedPreviousStation = "전역 출발"
    case unknown = "상태 정보 없음"
}

enum TrainDirection: Equatable, Sendable {
    case upOrInner
    case downOrOuter
    case unknown

    func displayName(for lineName: String) -> String {
        switch (self, lineName) {
        case (.upOrInner, "2호선"): return "내선"
        case (.downOrOuter, "2호선"): return "외선"
        case (.upOrInner, _): return "상행"
        case (.downOrOuter, _): return "하행"
        case (.unknown, _): return "방향 정보 없음"
        }
    }
}

enum TrainServiceType: String, Equatable, Sendable {
    case regular = "일반"
    case express = "급행"
    case limitedExpress = "특급"
}

struct TrainPosition: Identifiable, Equatable, Sendable {
    let id: String
    let lineName: String
    let stationID: String
    let currentStation: String
    let trainNumber: String
    let direction: TrainDirection
    let destinationStationID: String?
    let destination: String
    let status: TrainPositionStatus
    let serviceType: TrainServiceType
    let isLastTrain: Bool
    let receivedAt: Date?
    let remainingStationCount: Int?

    var directionText: String {
        direction.displayName(for: lineName)
    }

    func withRemainingStationCount(_ count: Int?) -> TrainPosition {
        TrainPosition(
            id: id,
            lineName: lineName,
            stationID: stationID,
            currentStation: currentStation,
            trainNumber: trainNumber,
            direction: direction,
            destinationStationID: destinationStationID,
            destination: destination,
            status: status,
            serviceType: serviceType,
            isLastTrain: isLastTrain,
            receivedAt: receivedAt,
            remainingStationCount: count
        )
    }

    func isStale(comparedTo now: Date = Date(), threshold: TimeInterval = 120) -> Bool {
        guard let receivedAt else { return true }
        return now.timeIntervalSince(receivedAt) > threshold
    }
}

enum TrainPositionDisplayPolicy {
    static let maximumPerLineAndDirection = 3

    static func select(
        from positions: [TrainPosition],
        maximumPerLineAndDirection maximum: Int = maximumPerLineAndDirection
    ) -> [TrainPosition] {
        guard maximum > 0 else { return [] }

        let sorted = positions.sorted {
            let lhsCount = $0.remainingStationCount ?? .max
            let rhsCount = $1.remainingStationCount ?? .max
            if lhsCount != rhsCount { return lhsCount < rhsCount }
            if $0.lineName != $1.lineName { return $0.lineName < $1.lineName }
            if $0.directionText != $1.directionText { return $0.directionText < $1.directionText }
            return $0.trainNumber < $1.trainNumber
        }

        var countsByGroup: [String: Int] = [:]
        return sorted.filter { position in
            let key = "\(position.lineName)|\(position.directionText)"
            let count = countsByGroup[key, default: 0]
            guard count < maximum else { return false }
            countsByGroup[key] = count + 1
            return true
        }
    }
}

struct LineRouteBundle: Decodable, Sendable {
    let lines: [LineRouteNetwork]
}

struct LineRouteNetwork: Decodable, Equatable, Sendable {
    let lineName: String
    let routes: [LineRoute]
}

struct LineRoute: Decodable, Equatable, Sendable {
    let id: String
    let isCircular: Bool
    let stationIDs: [String]
}

enum TrainRouteCalculator {
    static func remainingStationCount(
        for position: TrainPosition,
        selectedStationID: String,
        networks: [LineRouteNetwork]
    ) -> Int? {
        guard let network = networks.first(where: { $0.lineName == position.lineName }) else {
            return nil
        }

        return network.routes.compactMap { route in
            distance(
                on: route,
                from: position.stationID,
                to: selectedStationID,
                destination: position.destinationStationID,
                direction: position.direction
            )
        }.min()
    }

    private static func distance(
        on route: LineRoute,
        from currentStationID: String,
        to selectedStationID: String,
        destination destinationStationID: String?,
        direction: TrainDirection
    ) -> Int? {
        let currentIndices = indices(of: currentStationID, in: route.stationIDs)
        let selectedIndices = indices(of: selectedStationID, in: route.stationIDs)
        guard !currentIndices.isEmpty, !selectedIndices.isEmpty else { return nil }

        if currentStationID == selectedStationID {
            return 0
        }

        if route.isCircular {
            guard let destinationStationID,
                  !indices(of: destinationStationID, in: route.stationIDs).isEmpty else {
                return nil
            }
            let forward: Bool
            switch direction {
            case .upOrInner: forward = true
            case .downOrOuter: forward = false
            case .unknown: return nil
            }

            let destinationIndices = indices(of: destinationStationID, in: route.stationIDs)
            return currentIndices.flatMap { currentIndex in
                let destinationDistances = destinationIndices.map {
                    circularDistance(from: currentIndex, to: $0, count: route.stationIDs.count, forward: forward)
                }
                return selectedIndices.compactMap { selectedIndex -> Int? in
                    let selectedDistance = circularDistance(
                        from: currentIndex,
                        to: selectedIndex,
                        count: route.stationIDs.count,
                        forward: forward
                    )
                    return destinationDistances.contains(where: { selectedDistance <= $0 })
                        ? selectedDistance
                        : nil
                }
            }.min()
        }

        guard let destinationStationID else { return nil }
        let destinationIndices = indices(of: destinationStationID, in: route.stationIDs)
        guard !destinationIndices.isEmpty else { return nil }

        return currentIndices.flatMap { currentIndex in
            destinationIndices.flatMap { destinationIndex in
                selectedIndices.compactMap { selectedIndex -> Int? in
                    let lower = min(currentIndex, destinationIndex)
                    let upper = max(currentIndex, destinationIndex)
                    guard selectedIndex >= lower, selectedIndex <= upper else { return nil }
                    guard currentIndex != destinationIndex else { return nil }
                    let trainMovesForward = destinationIndex > currentIndex
                    let selectedIsAhead = trainMovesForward
                        ? selectedIndex >= currentIndex
                        : selectedIndex <= currentIndex
                    return selectedIsAhead ? abs(selectedIndex - currentIndex) : nil
                }
            }
        }.min()
    }

    private static func indices(of stationID: String, in stationIDs: [String]) -> [Int] {
        stationIDs.indices.filter { stationIDs[$0] == stationID }
    }

    private static func circularDistance(
        from start: Int,
        to end: Int,
        count: Int,
        forward: Bool
    ) -> Int {
        forward
            ? (end - start + count) % count
            : (start - end + count) % count
    }
}
