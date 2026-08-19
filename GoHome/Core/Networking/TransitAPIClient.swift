import Foundation

protocol TransitAPIClient: Sendable {
    func arrivals(at station: Station) async throws -> [TrainArrival]
    func positions(on lineName: String) async throws -> [TrainPosition]
}

enum TransitAPIError: LocalizedError, Equatable, Sendable {
    case missingProxyConfiguration
    case invalidURL
    case invalidProxyToken
    case rateLimitExceeded
    case workerConfiguration
    case workerUnavailable
    case seoulAPIUnavailable
    case invalidResponse
    case seoulAPI(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .missingProxyConfiguration:
            return "인증 설정이 없습니다. Config/Secrets.xcconfig에 Worker 주소와 호출 토큰을 설정해 주세요."
        case .invalidURL:
            return "실시간 정보 요청 주소를 만들 수 없습니다."
        case .invalidProxyToken:
            return "Worker 호출 토큰이 올바르지 않습니다. 로컬 설정과 배포된 Worker의 토큰을 확인해 주세요."
        case .rateLimitExceeded:
            return "실시간 정보 호출 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."
        case .workerConfiguration:
            return "Worker 인증 설정이 누락되었습니다. Worker Secret 설정을 확인해 주세요."
        case .workerUnavailable:
            return "실시간 정보 Worker에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요."
        case .seoulAPIUnavailable:
            return "서울시 실시간 API에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요."
        case .invalidResponse:
            return "실시간 정보 응답 형식이 예상과 다릅니다. 잠시 후 다시 시도해 주세요."
        case let .seoulAPI(code, message):
            return "서울시 API 오류(\(code)): \(message)"
        }
    }
}
