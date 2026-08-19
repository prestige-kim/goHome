import Combine
import CoreLocation
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    static let supportedRangeMeters: CLLocationDistance = 5_000
    static let automaticRefreshInterval: TimeInterval = 40

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var nearbyStations: [NearbyStation] = []
    @Published var selectedStation: Station?
    @Published var stationSearchText = "" {
        didSet { updateStationSearchResults() }
    }
    @Published private(set) var stationSearchResults: [Station] = []
    @Published private(set) var arrivals: [TrainArrival] = []
    @Published private(set) var isLoadingArrivals = false
    @Published private(set) var locationMessage: String?
    @Published private(set) var arrivalMessage: String?
    @Published private(set) var lastSuccessfulArrivalRefreshAt: Date?

    private let locationService: LocationService
    private let stationRepository: StationRepository
    private let transitClient: TransitAPIClient
    private let refreshInterval: TimeInterval
    private var stations: [Station] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasUserSelectedStation = false
    private var lastArrivalRequest: (stationID: String, startedAt: Date)?

    var latestArrivalReceivedAt: Date? {
        arrivals.compactMap(\.receivedAt).max()
    }

    var hasStaleArrivalData: Bool {
        hasStaleArrivalData(at: Date())
    }

    var isShowingLastSuccessfulData: Bool {
        !arrivals.isEmpty && arrivalMessage != nil
    }

    init(
        locationService: LocationService = LocationService(),
        stationRepository: StationRepository = BundledStationRepository(),
        transitClient: TransitAPIClient = DirectSeoulTransitAPIClient(
            baseURL: AppConfiguration.transitProxyBaseURL,
            clientToken: AppConfiguration.transitProxyClientToken
        ),
        automaticRefreshInterval: TimeInterval = HomeViewModel.automaticRefreshInterval
    ) {
        self.locationService = locationService
        self.stationRepository = stationRepository
        self.transitClient = transitClient
        refreshInterval = automaticRefreshInterval
        authorizationStatus = locationService.authorizationStatus
        accuracyAuthorization = locationService.accuracyAuthorization

        locationService.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
            }
            .store(in: &cancellables)

        locationService.$accuracyAuthorization
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accuracy in
                self?.accuracyAuthorization = accuracy
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
            updateStationSearchResults()
        } catch {
            locationMessage = error.localizedDescription
        }

        locationService.requestAccessAndLocation()
    }

    func refreshLocation() {
        hasUserSelectedStation = false
        locationService.refreshLocation()
    }

    func select(_ station: Station) {
        hasUserSelectedStation = true
        setSelectedStation(station)
    }

    private func setSelectedStation(_ station: Station) {
        guard selectedStation?.id != station.id else { return }
        selectedStation = station
        arrivals = []
        arrivalMessage = nil
        lastSuccessfulArrivalRefreshAt = nil
        lastArrivalRequest = nil
    }

    func refreshArrivals(isAutomatic: Bool = false, now: Date = Date()) async {
        guard let selectedStation else {
            if !isAutomatic {
                arrivalMessage = "먼저 가까운 역을 선택해 주세요."
            }
            return
        }

        guard !isLoadingArrivals else { return }

        if isAutomatic,
           let lastArrivalRequest,
           lastArrivalRequest.stationID == selectedStation.id,
           now.timeIntervalSince(lastArrivalRequest.startedAt) < refreshInterval {
            return
        }

        isLoadingArrivals = true
        arrivalMessage = nil
        lastArrivalRequest = (selectedStation.id, now)

        defer { isLoadingArrivals = false }

        do {
            let updatedArrivals = try await transitClient.arrivals(at: selectedStation)
            try Task.checkCancellation()
            guard self.selectedStation?.id == selectedStation.id else { return }

            arrivals = updatedArrivals
            lastSuccessfulArrivalRefreshAt = Date()
            if updatedArrivals.isEmpty {
                arrivalMessage = "현재 제공되는 도착정보가 없습니다."
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.selectedStation?.id == selectedStation.id else { return }
            arrivalMessage = error.localizedDescription
        }
    }

    func runAutomaticArrivalRefresh() async {
        guard selectedStation != nil else { return }

        while !Task.isCancelled {
            if let lastArrivalRequest,
               lastArrivalRequest.stationID == selectedStation?.id {
                let elapsed = Date().timeIntervalSince(lastArrivalRequest.startedAt)
                let remainingDelay = max(0, refreshInterval - elapsed)
                if remainingDelay > 0 {
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(remainingDelay * 1_000_000_000)
                        )
                    } catch {
                        return
                    }
                }
            }

            await refreshArrivals(isAutomatic: true)

            if lastArrivalRequest == nil {
                return
            }
        }
    }

    func hasStaleArrivalData(at date: Date) -> Bool {
        arrivals.contains { $0.isStale(comparedTo: date) }
    }

    private func updateNearbyStations(from location: CLLocation) {
        let resolution = StationDiscovery.nearbyStations(
            from: stations,
            location: location,
            supportedRange: Self.supportedRangeMeters
        )
        nearbyStations = resolution.candidates

        guard let first = nearbyStations.first else {
            locationMessage = "가까운 역을 계산할 수 없습니다."
            return
        }

        guard resolution.isNearestWithinSupportedRange else {
            if !hasUserSelectedStation {
                clearSelectedStation()
            }
            locationMessage = "지원되는 지하철역에서 5km 이상 떨어져 있습니다. 역을 직접 검색해 선택해 주세요."
            return
        }

        locationMessage = accuracyAuthorization == .reducedAccuracy
            ? "대략적인 위치를 사용 중입니다. 가까운 역이 정확하지 않으면 역을 직접 검색해 주세요."
            : nil
        if !hasUserSelectedStation {
            setSelectedStation(first.station)
        }
    }

    private func updateStationSearchResults() {
        stationSearchResults = StationDiscovery.search(stations, query: stationSearchText)
    }

    private func clearSelectedStation() {
        selectedStation = nil
        arrivals = []
        arrivalMessage = nil
        lastSuccessfulArrivalRefreshAt = nil
        lastArrivalRequest = nil
    }
}
