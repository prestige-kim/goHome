import Foundation

protocol TransitAPIClient {
    func arrivals(at station: Station) async throws -> [TrainArrival]
}

enum TransitAPIError: LocalizedError {
    case missingProxyConfiguration
    case invalidURL
    case invalidResponse
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .missingProxyConfiguration:
            return "Config/Secrets.xcconfig에 중계 서버 주소와 호출 토큰을 설정해 주세요."
        case .invalidURL:
            return "도착정보 요청 주소를 만들 수 없습니다."
        case .invalidResponse:
            return "도착정보 응답 형식이 예상과 다릅니다."
        case let .server(code, message):
            return "서울시 API 오류(\(code)): \(message)"
        }
    }
}
