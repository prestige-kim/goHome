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

    func serviceDay(for date: Date) async throws -> LastTrainServiceDayInfo {
        let (baseURL, clientToken) = try configuration()
        let serviceDate = TransitServiceClock.serviceDate(containing: date)
        let endpoint = baseURL.appendingPathComponent("v1/service-day")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TransitAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(
                name: "date",
                value: TransitServiceClock.isoDateString(from: serviceDate)
            ),
        ]
        guard let url = components.url else { throw TransitAPIError.invalidURL }

        let data = try await responseData(for: url, clientToken: clientToken)
        let payload: ServiceDayDTO
        do {
            payload = try JSONDecoder().decode(ServiceDayDTO.self, from: data)
        } catch {
            throw TransitAPIError.invalidResponse
        }
        guard let type = LastTrainServiceDay(rawValue: payload.type) else {
            throw TransitAPIError.invalidResponse
        }
        return LastTrainServiceDayInfo(
            date: serviceDate,
            type: type,
            holidayName: payload.holidayName,
            isHolidayVerified: true
        )
    }

    func lastTrains(
        at station: Station,
        serviceDay: LastTrainServiceDay,
        serviceDate: Date
    ) async throws -> [LastTrain] {
        let supportedLines = station.lineNames.filter(Self.timetableLines.contains)
        guard !supportedLines.isEmpty else { return [] }

        let requests = supportedLines.flatMap { lineName in
            let directions: [LastTrainDirection] = lineName == "2호선"
                ? [.inner, .outer, .up, .down]
                : [.up, .down]
            return directions.map { (lineName, $0) }
        }

        let results = await withTaskGroup(of: TimetableResult.self) { group in
            for (lineName, direction) in requests {
                group.addTask {
                    do {
                        return TimetableResult(
                            result: .success(
                                try await timetableRows(
                                    station: station,
                                    lineName: lineName,
                                    direction: direction,
                                    serviceDay: serviceDay,
                                    serviceDate: serviceDate
                                )
                            )
                        )
                    } catch is CancellationError {
                        return TimetableResult(result: .failure(.workerUnavailable))
                    } catch let error as TransitAPIError {
                        return TimetableResult(result: .failure(error))
                    } catch {
                        return TimetableResult(result: .failure(.timetableUnavailable))
                    }
                }
            }

            var values: [TimetableResult] = []
            for await value in group { values.append(value) }
            return values
        }

        var rows: [LastTrain] = []
        var firstError: TransitAPIError?
        var succeeded = false
        for result in results {
            switch result.result {
            case let .success(value):
                succeeded = true
                rows.append(contentsOf: value)
            case let .failure(error):
                firstError = firstError ?? error
            }
        }
        if !succeeded, let firstError { throw firstError }

        var latestByDestination: [String: LastTrain] = [:]
        for train in rows {
            let key = [
                train.lineName,
                train.direction.rawValue,
                train.destination,
                train.isExpress ? "express" : "regular",
            ].joined(separator: "|")
            if let existing = latestByDestination[key], existing.departureAt >= train.departureAt {
                continue
            }
            latestByDestination[key] = train
        }
        return latestByDestination.values.sorted {
            if $0.departureAt != $1.departureAt { return $0.departureAt < $1.departureAt }
            if $0.lineName != $1.lineName { return $0.lineName < $1.lineName }
            return $0.direction.rawValue < $1.direction.rawValue
        }
    }

    private func timetableRows(
        station: Station,
        lineName: String,
        direction: LastTrainDirection,
        serviceDay: LastTrainServiceDay,
        serviceDate: Date
    ) async throws -> [LastTrain] {
        let (baseURL, clientToken) = try configuration()
        let endpoint = baseURL.appendingPathComponent("v1/last-trains")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TransitAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "station", value: station.apiName),
            URLQueryItem(name: "line", value: lineName),
            URLQueryItem(name: "direction", value: direction.rawValue),
            URLQueryItem(name: "serviceDay", value: serviceDay.rawValue),
            URLQueryItem(name: "date", value: TransitServiceClock.isoDateString(from: serviceDate)),
        ]
        guard let url = components.url else { throw TransitAPIError.invalidURL }

        let data: Data
        do {
            data = try await responseData(for: url, clientToken: clientToken)
        } catch let error as TransitAPIError where error == .seoulAPIUnavailable {
            throw TransitAPIError.timetableUnavailable
        }

        let payload: SeoulTimetableEnvelope
        do {
            payload = try JSONDecoder().decode(SeoulTimetableEnvelope.self, from: data)
        } catch {
            throw TransitAPIError.invalidResponse
        }
        guard payload.response.header.resultCode == "00" else {
            throw TransitAPIError.timetableUnavailable
        }

        return (payload.response.body.items?.item ?? []).compactMap { item in
            guard item.lineNm == lineName,
                  item.stnNm == station.apiName,
                  item.upbdnbSe == direction.title,
                  let departureAt = TransitServiceClock.departureDate(
                    time: item.trainDptreTm,
                    serviceDate: serviceDate
                  ) else {
                return nil
            }
            let destination = item.arvlStnNm ?? "종착역 정보 없음"
            let trainNumber = item.trainno ?? "열차번호 없음"
            let isExpress = item.etrnYn == "Y" || item.trainKnd?.contains("급행") == true
            return LastTrain(
                id: [lineName, direction.rawValue, destination, trainNumber, item.trainDptreTm]
                    .joined(separator: "-"),
                lineName: lineName,
                direction: direction,
                destination: destination,
                trainNumber: trainNumber,
                departureAt: departureAt,
                serviceDate: serviceDate,
                serviceDay: serviceDay,
                isExpress: isExpress
            )
        }
    }

    private func configuration() throws -> (URL, String) {
        guard let baseURL,
              baseURL.scheme?.lowercased() == "https",
              let clientToken,
              !clientToken.isEmpty else {
            throw TransitAPIError.missingProxyConfiguration
        }
        return (baseURL, clientToken)
    }

    private func responseData(for url: URL, clientToken: String) async throws -> Data {
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
        return data
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
        case 500 where proxyError == "missing_public_data_api_key":
            return .holidayConfiguration
        case 502 where proxyError == "holiday_api_unavailable":
            return .holidayAPIUnavailable
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

    private static let timetableLines: Set<String> = [
        "1호선", "2호선", "3호선", "4호선", "5호선", "6호선", "7호선", "8호선", "9호선",
    ]
}

private struct TimetableResult: Sendable {
    let result: Result<[LastTrain], TransitAPIError>
}

private struct ServiceDayDTO: Decodable {
    let type: String
    let holidayName: String?
}

private struct SeoulTimetableEnvelope: Decodable {
    let response: SeoulTimetableResponse
}

private struct SeoulTimetableResponse: Decodable {
    let header: SeoulTimetableHeader
    let body: SeoulTimetableBody
}

private struct SeoulTimetableHeader: Decodable {
    let resultCode: String
}

private struct SeoulTimetableBody: Decodable {
    let items: SeoulTimetableItems?
}

private struct SeoulTimetableItems: Decodable {
    let item: [SeoulTimetableDTO]
}

private struct SeoulTimetableDTO: Decodable {
    let trainno: String?
    let trainKnd: String?
    let upbdnbSe: String
    let lineNm: String
    let stnNm: String
    let arvlStnNm: String?
    let trainDptreTm: String
    let etrnYn: String?
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
