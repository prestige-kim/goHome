import Foundation

protocol TransitAPIClient: Sendable {
    func arrivals(at station: Station) async throws -> [TrainArrival]
    func positions(on lineName: String) async throws -> [TrainPosition]
    func serviceDay(for date: Date) async throws -> LastTrainServiceDayInfo
    func lastTrains(
        at station: Station,
        serviceDay: LastTrainServiceDay,
        serviceDate: Date
    ) async throws -> [LastTrain]
}

extension TransitAPIClient {
    func serviceDay(for date: Date) async throws -> LastTrainServiceDayInfo {
        throw TransitAPIError.timetableUnavailable
    }

    func lastTrains(
        at station: Station,
        serviceDay: LastTrainServiceDay,
        serviceDate: Date
    ) async throws -> [LastTrain] {
        throw TransitAPIError.timetableUnavailable
    }
}

enum TransitAPIError: LocalizedError, Equatable, Sendable {
    case missingProxyConfiguration
    case invalidURL
    case invalidProxyToken
    case rateLimitExceeded
    case workerConfiguration
    case workerUnavailable
    case seoulAPIUnavailable
    case timetableUnavailable
    case holidayConfiguration
    case holidayAPIUnavailable
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
        case .timetableUnavailable:
            return "막차 예정 시간표를 불러올 수 없습니다. 잠시 후 다시 시도해 주세요."
        case .holidayConfiguration:
            return "공휴일 확인 설정이 없습니다. Worker의 공공데이터포털 키를 확인해 주세요."
        case .holidayAPIUnavailable:
            return "공휴일 정보를 확인할 수 없습니다. 요일 기준 시간표를 표시합니다."
        case .invalidResponse:
            return "실시간 정보 응답 형식이 예상과 다릅니다. 잠시 후 다시 시도해 주세요."
        case let .seoulAPI(code, message):
            return "서울시 API 오류(\(code)): \(message)"
        }
    }
}
