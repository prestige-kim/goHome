import Foundation

enum TrainArrivalStatus: String, Equatable, Sendable {
    case approaching = "진입"
    case arrived = "도착"
    case departed = "출발"
    case departedPreviousStation = "전역 출발"
    case approachingPreviousStation = "전역 진입"
    case arrivedPreviousStation = "전역 도착"
    case inTransit = "운행 중"
    case unknown = "상태 정보 없음"
}

struct TrainArrival: Identifiable, Equatable, Sendable {
    let id: String
    let lineName: String
    let direction: String
    let destination: String
    let remainingSeconds: Int?
    let message: String
    let status: TrainArrivalStatus
    let isExpress: Bool
    let isLastTrain: Bool
    let receivedAt: Date?

    func isStale(comparedTo now: Date = Date(), threshold: TimeInterval = 120) -> Bool {
        guard let receivedAt else { return true }
        return now.timeIntervalSince(receivedAt) > threshold
    }
}
