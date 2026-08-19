import Foundation

protocol StationRepository {
    func loadStations() throws -> [Station]
}

struct BundledStationRepository: StationRepository {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadStations() throws -> [Station] {
        guard let url = bundle.url(forResource: "stations.seed", withExtension: "json") else {
            throw StationRepositoryError.missingResource
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Station].self, from: data)
    }
}

enum StationRepositoryError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "번들에서 역 좌표 데이터를 찾을 수 없습니다."
        }
    }
}
