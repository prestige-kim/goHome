import Foundation

struct DirectSeoulTransitAPIClient: TransitAPIClient {
    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func arrivals(at station: Station) async throws -> [TrainArrival] {
        guard let apiKey, !apiKey.isEmpty else {
            throw TransitAPIError.missingAPIKey
        }

        guard let encodedStation = station.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(
                string: "https://swopenapi.seoul.go.kr/api/subway/\(apiKey)/json/realtimeStationArrival/0/20/\(encodedStation)"
              ) else {
            throw TransitAPIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TransitAPIError.invalidResponse
        }

        let payload = try JSONDecoder().decode(SeoulArrivalResponse.self, from: data)

        if let error = payload.errorMessage, error.code != "INFO-000" {
            throw TransitAPIError.server(code: error.code, message: error.message)
        }

        return (payload.realtimeArrivalList ?? []).map { item in
            TrainArrival(
                id: [item.subwayId, item.trainLineNm, item.btrainNo, item.recptnDt]
                    .compactMap { $0 }
                    .joined(separator: "-"),
                lineName: item.subwayName,
                direction: item.updnLine ?? "방향 정보 없음",
                destination: item.destination,
                remainingSeconds: item.barvlDt.flatMap(Int.init),
                message: item.arvlMsg2 ?? "도착정보 없음",
                receivedAt: item.recptnDt ?? ""
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
    let statnNm: String?
    let barvlDt: String?
    let arvlMsg2: String?
    let btrainNo: String?
    let bstatnNm: String?
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
        case "1092": return "우이신설선"
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
}
