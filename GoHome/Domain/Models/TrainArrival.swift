import Foundation

struct TrainArrival: Identifiable, Equatable, Sendable {
    let id: String
    let lineName: String
    let direction: String
    let destination: String
    let remainingSeconds: Int?
    let message: String
    let receivedAt: String
}
