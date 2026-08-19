import Combine
import CoreLocation
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    static let supportedRangeMeters: CLLocationDistance = 5_000

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var nearbyStations: [NearbyStation] = []
    @Published var selectedStation: Station?
    @Published private(set) var arrivals: [TrainArrival] = []
    @Published private(set) var isLoadingArrivals = false
    @Published private(set) var locationMessage: String?
    @Published private(set) var arrivalMessage: String?

    private let locationService: LocationService
    private let stationRepository: StationRepository
    private let transitClient: TransitAPIClient
    private var stations: [Station] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false

    var latestArrivalReceivedAt: Date? {
        arrivals.compactMap(\.receivedAt).max()
    }

    var hasStaleArrivalData: Bool {
        arrivals.contains { $0.isStale() }
    }

    init(
        locationService: LocationService = LocationService(),
        stationRepository: StationRepository = BundledStationRepository(),
        transitClient: TransitAPIClient = DirectSeoulTransitAPIClient(
            baseURL: AppConfiguration.transitProxyBaseURL,
            clientToken: AppConfiguration.transitProxyClientToken
        )
    ) {
        self.locationService = locationService
        self.stationRepository = stationRepository
        self.transitClient = transitClient
        authorizationStatus = locationService.authorizationStatus

        locationService.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
            }
            .store(in: &cancellables)

        locationService.$location
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.updateNearbyStations(from: location)
            }
            .store(in: &cancellables)

        locationService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.locationMessage = message
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            stations = try stationRepository.loadStations()
        } catch {
            locationMessage = error.localizedDescription
        }

        locationService.requestAccessAndLocation()
    }

    func refreshLocation() {
        locationService.refreshLocation()
    }

    func select(_ station: Station) {
        selectedStation = station
        arrivals = []
        arrivalMessage = nil
    }

    func refreshArrivals() async {
        guard let selectedStation else {
            arrivalMessage = "먼저 가까운 역을 선택해 주세요."
            return
        }

        isLoadingArrivals = true
        arrivalMessage = nil

        defer { isLoadingArrivals = false }

        do {
            arrivals = try await transitClient.arrivals(at: selectedStation)
            if arrivals.isEmpty {
                arrivalMessage = "현재 제공되는 도착정보가 없습니다."
            }
        } catch {
            arrivalMessage = error.localizedDescription
        }
    }

    private func updateNearbyStations(from location: CLLocation) {
        let nearby = stations
            .map { NearbyStation(station: $0, distance: $0.distance(from: location)) }
            .sorted { $0.distance < $1.distance }
            .prefix(3)

        nearbyStations = Array(nearby)

        guard let first = nearbyStations.first else {
            locationMessage = "가까운 역을 계산할 수 없습니다."
            return
        }

        guard first.distance <= Self.supportedRangeMeters else {
            selectedStation = nil
            locationMessage = "지원되는 지하철역에서 5km 이상 떨어져 있습니다. 위치를 다시 확인해 주세요."
            return
        }

        locationMessage = nil
        if selectedStation == nil {
            selectedStation = first.station
        }
    }
}
