import Foundation

struct DirectSeoulTransitAPIClient: TransitAPIClient {
    private let baseURL: URL?
    private let clientToken: String?
    private let session: URLSession

    init(baseURL: URL?, clientToken: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.clientToken = clientToken
        self.session = session
    }

    func arrivals(at station: Station) async throws -> [TrainArrival] {
        guard let baseURL,
              baseURL.scheme?.lowercased() == "https",
              let clientToken,
              !clientToken.isEmpty else {
            throw TransitAPIError.missingProxyConfiguration
        }

        let endpoint = baseURL.appendingPathComponent("v1/arrivals")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TransitAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "station", value: station.apiName)]
        guard let url = components.url else {
            throw TransitAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TransitAPIError.workerUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransitAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw error(for: httpResponse.statusCode, data: data)
        }

        let payload: SeoulArrivalResponse
        do {
            payload = try JSONDecoder().decode(SeoulArrivalResponse.self, from: data)
        } catch {
            throw TransitAPIError.invalidResponse
        }

        guard let apiMessage = payload.apiMessage else {
            throw TransitAPIError.invalidResponse
        }

        if apiMessage.code != "INFO-000" {
            if Self.isRateLimitMessage(apiMessage.message) {
                throw TransitAPIError.rateLimitExceeded
            }
            throw TransitAPIError.seoulAPI(code: apiMessage.code, message: apiMessage.message)
        }

        let stationIDs = Set(station.seoulStationIDs.values)
        let matchingArrivals = (payload.realtimeArrivalList ?? []).filter { item in
            stationIDs.isEmpty || item.statnId.map(stationIDs.contains) == true
        }

        return matchingArrivals.map { item in
            TrainArrival(
                id: [item.statnId, item.subwayId, item.ordkey, item.btrainNo, item.recptnDt]
                    .compactMap { $0 }
                    .joined(separator: "-"),
                lineName: item.subwayName,
                direction: item.updnLine ?? "방향 정보 없음",
                destination: item.destination,
                remainingSeconds: item.barvlDt.flatMap(Int.init),
                message: item.arvlMsg2 ?? "도착정보 없음",
                status: item.arrivalStatus,
                isExpress: item.btrainSttus == "급행" || item.trainLineNm?.contains("(급행)") == true,
                isLastTrain: item.lstcarAt == "1",
                receivedAt: item.receivedDate
            )
        }
    }

    func positions(on lineName: String) async throws -> [TrainPosition] {
        guard let baseURL,
              baseURL.scheme?.lowercased() == "https",
              let clientToken,
              !clientToken.isEmpty else {
            throw TransitAPIError.missingProxyConfiguration
        }

        let endpoint = baseURL.appendingPathComponent("v1/positions")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TransitAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "line", value: lineName)]
        guard let url = components.url else {
            throw TransitAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TransitAPIError.workerUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransitAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw error(for: httpResponse.statusCode, data: data)
        }

        let payload: SeoulPositionResponse
        do {
            payload = try JSONDecoder().decode(SeoulPositionResponse.self, from: data)
        } catch {
            throw TransitAPIError.invalidResponse
        }

        guard let apiMessage = payload.apiMessage else {
            throw TransitAPIError.invalidResponse
        }
        if apiMessage.code != "INFO-000" {
            if Self.isRateLimitMessage(apiMessage.message) {
                throw TransitAPIError.rateLimitExceeded
            }
            throw TransitAPIError.seoulAPI(code: apiMessage.code, message: apiMessage.message)
        }

        let latestPositions = Self.latestPositionItems(payload.realtimePositionList ?? [])
        return latestPositions.map { item in
            TrainPosition(
                id: [item.subwayId, item.trainNo, item.recptnDt]
                    .compactMap { $0 }
                    .joined(separator: "-"),
                lineName: item.subwayNm ?? item.subwayName,
                stationID: item.statnId ?? "",
                currentStation: item.statnNm ?? "현재 역 정보 없음",
                trainNumber: item.trainNo ?? "열차번호 없음",
                direction: item.direction,
                destinationStationID: item.statnTid,
                destination: item.statnTnm ?? "종착역 정보 없음",
                status: item.positionStatus,
                serviceType: item.serviceType,
                isLastTrain: item.lstcarAt == "1",
                receivedAt: item.receivedDate,
                remainingStationCount: nil
            )
        }
    }

    private func error(for statusCode: Int, data: Data) -> TransitAPIError {
        let proxyError = (try? JSONDecoder().decode(ProxyErrorResponse.self, from: data))?.error

        switch statusCode {
        case 401, 403:
            return .invalidProxyToken
        case 429:
            return .rateLimitExceeded
        case 500 where proxyError == "missing_seoul_api_key" || proxyError == "missing_client_token":
            return .workerConfiguration
        case 502 where proxyError == "upstream_http_error" ||
            proxyError == "upstream_unavailable" ||
            proxyError == "invalid_upstream_response":
            return .seoulAPIUnavailable
        case 500...599:
            return .workerUnavailable
        default:
            return .invalidResponse
        }
    }

    private static func isRateLimitMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return ["호출 한도", "요청 한도", "일일 한도", "초과", "rate limit", "quota"]
            .contains { normalized.contains($0) }
    }

    private static func latestPositionItems(
        _ items: [SeoulPositionDTO]
    ) -> [SeoulPositionDTO] {
        var latestByTrain: [String: (firstIndex: Int, item: SeoulPositionDTO)] = [:]
        var unidentified: [(index: Int, item: SeoulPositionDTO)] = []

        for (index, item) in items.enumerated() {
            guard let trainNumber = item.trainNo?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trainNumber.isEmpty else {
                unidentified.append((index, item))
                continue
            }

            let lineIdentifier = item.subwayId ?? item.subwayNm ?? "unknown-line"
            let key = "\(lineIdentifier)|\(trainNumber)"
            guard let existing = latestByTrain[key] else {
                latestByTrain[key] = (index, item)
                continue
            }

            let existingDate = existing.item.receivedDate
            let candidateDate = item.receivedDate
            let shouldReplace = switch (existingDate, candidateDate) {
            case (nil, _): true
            case (_, nil): false
            case let (existingDate?, candidateDate?): candidateDate >= existingDate
            }
            if shouldReplace {
                latestByTrain[key] = (existing.firstIndex, item)
            }
        }

        return (latestByTrain.values.map { ($0.firstIndex, $0.item) } + unidentified)
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }
}

private struct SeoulArrivalResponse: Decodable {
    let errorMessage: SeoulAPIMessage?
    let result: SeoulAPIResult?
    let realtimeArrivalList: [SeoulArrivalDTO]?

    var apiMessage: SeoulAPIMessage? {
        if let errorMessage {
            return errorMessage
        }
        if let result {
            return SeoulAPIMessage(code: result.code, message: result.message)
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case errorMessage
        case result = "RESULT"
        case realtimeArrivalList
    }
}

private struct SeoulPositionResponse: Decodable {
    let errorMessage: SeoulAPIMessage?
    let result: SeoulAPIResult?
    let realtimePositionList: [SeoulPositionDTO]?

    var apiMessage: SeoulAPIMessage? {
        if let errorMessage {
            return errorMessage
        }
        if let result {
            return SeoulAPIMessage(code: result.code, message: result.message)
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case errorMessage
        case result = "RESULT"
        case realtimePositionList
    }
}

private struct SeoulAPIResult: Decodable {
    let code: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case code = "CODE"
        case message = "MESSAGE"
    }
}

private struct ProxyErrorResponse: Decodable {
    let error: String
}

private struct SeoulAPIMessage: Decodable {
    let code: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case code = "code"
        case message = "message"
    }
}

private struct SeoulArrivalDTO: Decodable {
    let subwayId: String?
    let updnLine: String?
    let trainLineNm: String?
    let statnId: String?
    let statnNm: String?
    let barvlDt: String?
    let arvlMsg2: String?
    let arvlCd: String?
    let btrainNo: String?
    let bstatnNm: String?
    let btrainSttus: String?
    let lstcarAt: String?
    let ordkey: String?
    let recptnDt: String?

    var subwayName: String {
        switch subwayId {
        case "1001": return "1호선"
        case "1002": return "2호선"
        case "1003": return "3호선"
        case "1004": return "4호선"
        case "1005": return "5호선"
        case "1006": return "6호선"
        case "1007": return "7호선"
        case "1008": return "8호선"
        case "1009": return "9호선"
        case "1063": return "경의중앙선"
        case "1065": return "공항철도"
        case "1067": return "경춘선"
        case "1075": return "수인분당선"
        case "1077": return "신분당선"
        case "1081": return "경강선"
        case "1092": return "우이신설선"
        case "1093": return "서해선"
        case "1094": return "신림선"
        case "1032": return "GTX-A"
        default: return subwayId ?? "노선 정보 없음"
        }
    }

    var destination: String {
        if let bstatnNm, !bstatnNm.isEmpty {
            return bstatnNm + "행"
        }
        return trainLineNm ?? "종착역 정보 없음"
    }

    var arrivalStatus: TrainArrivalStatus {
        switch arvlCd {
        case "0": return .approaching
        case "1": return .arrived
        case "2": return .departed
        case "3": return .departedPreviousStation
        case "4": return .approachingPreviousStation
        case "5": return .arrivedPreviousStation
        case "99": return .inTransit
        default: return .unknown
        }
    }

    var receivedDate: Date? {
        guard let recptnDt else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: recptnDt)
    }
}

private struct SeoulPositionDTO: Decodable {
    let subwayId: String?
    let subwayNm: String?
    let statnId: String?
    let statnNm: String?
    let trainNo: String?
    let lastRecptnDt: String?
    let recptnDt: String?
    let updnLine: String?
    let statnTid: String?
    let statnTnm: String?
    let trainSttus: String?
    let directAt: String?
    let lstcarAt: String?

    var subwayName: String {
        switch subwayId {
        case "1001": return "1호선"
        case "1002": return "2호선"
        case "1003": return "3호선"
        case "1004": return "4호선"
        case "1005": return "5호선"
        case "1006": return "6호선"
        case "1007": return "7호선"
        case "1008": return "8호선"
        case "1009": return "9호선"
        case "1063": return "경의중앙선"
        case "1065": return "공항철도"
        case "1067": return "경춘선"
        case "1075": return "수인분당선"
        case "1077": return "신분당선"
        case "1081": return "경강선"
        case "1092": return "우이신설선"
        case "1093": return "서해선"
        case "1094": return "신림선"
        case "1032": return "GTX-A"
        default: return subwayId ?? "노선 정보 없음"
        }
    }

    var direction: TrainDirection {
        switch updnLine {
        case "0": return .upOrInner
        case "1": return .downOrOuter
        default: return .unknown
        }
    }

    var positionStatus: TrainPositionStatus {
        switch trainSttus {
        case "0": return .approaching
        case "1": return .arrived
        case "2": return .departed
        case "3": return .departedPreviousStation
        default: return .unknown
        }
    }

    var serviceType: TrainServiceType {
        switch directAt {
        case "1": return .express
        case "7": return .limitedExpress
        default: return .regular
        }
    }

    var receivedDate: Date? {
        guard let recptnDt else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: recptnDt)
    }
}
