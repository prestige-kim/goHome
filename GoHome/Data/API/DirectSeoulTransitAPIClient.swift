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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TransitAPIError.invalidResponse
        }

        let payload = try JSONDecoder().decode(SeoulArrivalResponse.self, from: data)

        if let error = payload.errorMessage, error.code != "INFO-000" {
            throw TransitAPIError.server(code: error.code, message: error.message)
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
}

private struct SeoulArrivalResponse: Decodable {
    let errorMessage: SeoulAPIMessage?
    let realtimeArrivalList: [SeoulArrivalDTO]?
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
