import Foundation

protocol LineRouteRepository {
    func loadLineRoutes() throws -> [LineRouteNetwork]
}

struct BundledLineRouteRepository: LineRouteRepository {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadLineRoutes() throws -> [LineRouteNetwork] {
        guard let url = bundle.url(forResource: "line_routes", withExtension: "json") else {
            throw LineRouteRepositoryError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LineRouteBundle.self, from: data).lines
    }
}

enum LineRouteRepositoryError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        "노선 순서 데이터를 찾을 수 없습니다."
    }
}
