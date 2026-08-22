import Combine
import CoreLocation
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    nonisolated static let supportedRangeMeters: CLLocationDistance = 5_000
    nonisolated static let automaticRefreshInterval: TimeInterval = 40
    nonisolated static let maximumAutomaticRefreshInterval: TimeInterval = 5 * 60
    nonisolated static let automaticRefreshSessionDuration: TimeInterval = 30 * 60
    nonisolated static let lastTrainCacheTTL: TimeInterval = 6 * 60 * 60

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var nearbyStations: [NearbyStation] = []
    @Published var selectedStation: Station?
    @Published var stationSearchText = "" {
        didSet { updateStationSearchResults() }
    }
    @Published private(set) var stationSearchResults: [Station] = []
    @Published private(set) var arrivals: [TrainArrival] = []
    @Published private(set) var positions: [TrainPosition] = []
    @Published private(set) var lastTrains: [LastTrain] = []
    @Published var lastTrainDaySelection: LastTrainDaySelection = .automatic
    @Published private(set) var isLoadingArrivals = false
    @Published private(set) var isLoadingPositions = false
    @Published private(set) var isLoadingLastTrains = false
    @Published private(set) var locationMessage: String?
    @Published private(set) var arrivalMessage: String?
    @Published private(set) var positionMessage: String?
    @Published private(set) var lastTrainMessage: String?
    @Published private(set) var lastSuccessfulArrivalRefreshAt: Date?
    @Published private(set) var lastSuccessfulPositionRefreshAt: Date?
    @Published private(set) var lastSuccessfulLastTrainRefreshAt: Date?
    @Published private(set) var lastTrainServiceDayInfo: LastTrainServiceDayInfo?
    @Published private(set) var isUsingRetainedLastTrainData = false
    @Published private(set) var isAutomaticRefreshPaused = false

    private let locationService: LocationService
    private let stationRepository: StationRepository
    private let lineRouteRepository: LineRouteRepository
    private let transitClient: TransitAPIClient
    private let refreshInterval: TimeInterval
    private let refreshSessionDuration: TimeInterval
    private var stations: [Station] = []
    private var lineRouteNetworks: [LineRouteNetwork] = []
    private var lineRouteLoadMessage: String?
    private var positionsByLine: [String: [TrainPosition]] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasUserSelectedStation = false
    private var lastTransitRequest: (stationID: String, startedAt: Date)?
    private var consecutiveTransitFailures = 0
    private var automaticRefreshSessionDeadline: Date?
    private var lastTrainCacheKey: String?

    var latestArrivalReceivedAt: Date? {
        arrivals.compactMap(\.receivedAt).max()
    }

    var hasStaleArrivalData: Bool {
        hasStaleArrivalData(at: Date())
    }

    var latestPositionReceivedAt: Date? {
        positions.compactMap(\.receivedAt).max()
    }

    var hasStalePositionData: Bool {
        hasStalePositionData(at: Date())
    }

    var isShowingLastSuccessfulData: Bool {
        !arrivals.isEmpty && arrivalMessage != nil
    }

    var isShowingLastSuccessfulPositionData: Bool {
        !positions.isEmpty && positionMessage != nil
    }

    var isLoadingTransitData: Bool {
        isLoadingArrivals || isLoadingPositions
    }

    var isLoadingAnyData: Bool {
        isLoadingTransitData || isLoadingLastTrains
    }

    var isShowingLastSuccessfulLastTrainData: Bool {
        isUsingRetainedLastTrainData
    }

    var displayedPositions: [TrainPosition] {
        TrainPositionDisplayPolicy.select(from: positions)
    }

    var isPositionListLimited: Bool {
        displayedPositions.count < positions.count
    }

    init(
        locationService: LocationService? = nil,
        stationRepository: StationRepository = BundledStationRepository(),
        lineRouteRepository: LineRouteRepository = BundledLineRouteRepository(),
        transitClient: TransitAPIClient = DirectSeoulTransitAPIClient(
            baseURL: AppConfiguration.transitProxyBaseURL,
            clientToken: AppConfiguration.transitProxyClientToken
        ),
        automaticRefreshInterval: TimeInterval = HomeViewModel.automaticRefreshInterval,
        automaticRefreshSessionDuration: TimeInterval = HomeViewModel.automaticRefreshSessionDuration
    ) {
        let locationService = locationService ?? LocationService()
        self.locationService = locationService
        self.stationRepository = stationRepository
        self.lineRouteRepository = lineRouteRepository
        self.transitClient = transitClient
        refreshInterval = automaticRefreshInterval
        refreshSessionDuration = automaticRefreshSessionDuration
        authorizationStatus = locationService.authorizationStatus
        accuracyAuthorization = locationService.accuracyAuthorization

        do {
            lineRouteNetworks = try lineRouteRepository.loadLineRoutes()
        } catch {
            lineRouteLoadMessage = error.localizedDescription
            positionMessage = error.localizedDescription
        }

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
        positions = []
        lastTrains = []
        positionsByLine = [:]
        arrivalMessage = nil
        positionMessage = lineRouteLoadMessage
        lastTrainMessage = nil
        lastSuccessfulArrivalRefreshAt = nil
        lastSuccessfulPositionRefreshAt = nil
        lastSuccessfulLastTrainRefreshAt = nil
        lastTrainServiceDayInfo = nil
        isUsingRetainedLastTrainData = false
        lastTransitRequest = nil
        consecutiveTransitFailures = 0
        automaticRefreshSessionDeadline = nil
        isAutomaticRefreshPaused = false
        lastTrainCacheKey = nil
    }

    func refreshArrivals(isAutomatic: Bool = false, now: Date = Date()) async {
        if !isAutomatic {
            resumeAutomaticRefreshSession(now: now)
        }
        guard let selectedStation else {
            if !isAutomatic {
                arrivalMessage = "먼저 가까운 역을 선택해 주세요."
            }
            return
        }

        guard !isLoadingTransitData else { return }

        if isAutomatic,
           let lastTransitRequest,
           lastTransitRequest.stationID == selectedStation.id,
           now.timeIntervalSince(lastTransitRequest.startedAt) < refreshInterval {
            return
        }

        isLoadingArrivals = true
        isLoadingPositions = true
        arrivalMessage = nil
        positionMessage = lineRouteLoadMessage
        lastTransitRequest = (selectedStation.id, now)

        defer {
            isLoadingArrivals = false
            isLoadingPositions = false
        }

        var arrivalSucceeded = false

        do {
            let updatedArrivals = try await transitClient.arrivals(at: selectedStation)
            try Task.checkCancellation()
            guard self.selectedStation?.id == selectedStation.id else { return }

            arrivals = updatedArrivals
            arrivalSucceeded = true
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


        guard !Task.isCancelled, self.selectedStation?.id == selectedStation.id else { return }
        let positionResults = await fetchPositions(for: selectedStation.lineNames)
        guard !Task.isCancelled, self.selectedStation?.id == selectedStation.id else { return }

        var failedLines: [String] = []
        var firstError: TransitAPIError?
        var succeeded = false
        for result in positionResults {
            switch result.result {
            case let .success(updatedPositions):
                succeeded = true
                let selectedStationID = selectedStation.seoulStationIDs[result.lineName]
                positionsByLine[result.lineName] = updatedPositions.compactMap { position in
                    guard let selectedStationID else { return nil }
                    let remainingCount = TrainRouteCalculator.remainingStationCount(
                        for: position,
                        selectedStationID: selectedStationID,
                        networks: lineRouteNetworks
                    )
                    guard remainingCount != nil else { return nil }
                    return position.withRemainingStationCount(remainingCount)
                }
            case let .failure(error):
                failedLines.append(result.lineName)
                firstError = firstError ?? error
            }
        }

        positions = selectedStation.lineNames
            .flatMap { positionsByLine[$0] ?? [] }
            .sorted {
                let lhsCount = $0.remainingStationCount ?? .max
                let rhsCount = $1.remainingStationCount ?? .max
                if lhsCount != rhsCount { return lhsCount < rhsCount }
                if $0.lineName != $1.lineName { return $0.lineName < $1.lineName }
                return $0.trainNumber < $1.trainNumber
            }

        if succeeded {
            lastSuccessfulPositionRefreshAt = Date()
        }
        if !failedLines.isEmpty {
            let detail = firstError?.localizedDescription ?? TransitAPIError.workerUnavailable.localizedDescription
            positionMessage = "\(failedLines.joined(separator: ", ")) 위치정보 갱신 실패 · \(detail)"
        } else if let lineRouteLoadMessage {
            positionMessage = lineRouteLoadMessage
        } else if positions.isEmpty {
            positionMessage = "현재 선택 역으로 접근 중인 열차 위치가 없습니다."
        } else {
            positionMessage = nil
        }

        if arrivalSucceeded && failedLines.isEmpty {
            consecutiveTransitFailures = 0
        } else {
            consecutiveTransitFailures = min(consecutiveTransitFailures + 1, 8)
        }
    }

    func refreshAll(now: Date = Date()) async {
        await refreshArrivals(now: now)
        await refreshLastTrains(force: true, now: now)
    }

    func refreshLastTrains(force: Bool = false, now: Date = Date()) async {
        guard let selectedStation else {
            lastTrainMessage = "먼저 가까운 역을 선택해 주세요."
            return
        }
        let supportedLines = selectedStation.lineNames.filter(Self.timetableLines.contains)
        guard !supportedLines.isEmpty else {
            lastTrains = []
            lastTrainMessage = "예정 막차 시간표는 현재 서울교통공사 1~9호선에서 제공합니다."
            lastTrainServiceDayInfo = nil
            isUsingRetainedLastTrainData = false
            return
        }

        let serviceDate = TransitServiceClock.serviceDate(containing: now)
        let cacheKey = [
            selectedStation.id,
            lastTrainDaySelection.rawValue,
            TransitServiceClock.isoDateString(from: serviceDate),
        ].joined(separator: ":")
        if !force,
           cacheKey == lastTrainCacheKey,
           let lastSuccessfulLastTrainRefreshAt,
           now.timeIntervalSince(lastSuccessfulLastTrainRefreshAt) < Self.lastTrainCacheTTL {
            return
        }
        guard !isLoadingLastTrains else { return }

        isLoadingLastTrains = true
        lastTrainMessage = nil
        defer { isLoadingLastTrains = false }

        let serviceDayInfo: LastTrainServiceDayInfo
        if let fixed = lastTrainDaySelection.fixedServiceDay {
            serviceDayInfo = LastTrainServiceDayInfo(
                date: serviceDate,
                type: fixed,
                holidayName: nil,
                isHolidayVerified: false
            )
        } else {
            do {
                serviceDayInfo = try await transitClient.serviceDay(for: now)
            } catch is CancellationError {
                return
            } catch {
                serviceDayInfo = LastTrainServiceDayInfo(
                    date: serviceDate,
                    type: TransitServiceClock.localServiceDay(for: serviceDate),
                    holidayName: nil,
                    isHolidayVerified: false
                )
                lastTrainMessage = "공휴일 확인에 실패해 요일 기준 시간표를 표시합니다."
            }
        }

        do {
            let updated = try await transitClient.lastTrains(
                at: selectedStation,
                serviceDay: serviceDayInfo.type,
                serviceDate: serviceDate
            )
            try Task.checkCancellation()
            guard self.selectedStation?.id == selectedStation.id else { return }

            lastTrains = updated
            lastTrainServiceDayInfo = serviceDayInfo
            lastSuccessfulLastTrainRefreshAt = now
            lastTrainCacheKey = cacheKey
            isUsingRetainedLastTrainData = false
            if updated.isEmpty {
                lastTrainMessage = "선택한 영업일의 막차 예정 시간표가 없습니다."
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.selectedStation?.id == selectedStation.id else { return }
            lastTrainMessage = error.localizedDescription
            isUsingRetainedLastTrainData = !lastTrains.isEmpty
        }
    }

    func runAutomaticArrivalRefresh() async {
        guard selectedStation != nil else { return }
        resumeAutomaticRefreshSession(now: Date())

        while !Task.isCancelled {
            if let deadline = automaticRefreshSessionDeadline, Date() >= deadline {
                isAutomaticRefreshPaused = true
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                continue
            }

            if let lastTransitRequest,
               lastTransitRequest.stationID == selectedStation?.id {
                let elapsed = Date().timeIntervalSince(lastTransitRequest.startedAt)
                let remainingDelay = max(0, currentAutomaticRefreshInterval - elapsed)
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

            if lastTransitRequest == nil {
                return
            }
        }
    }

    func hasStaleArrivalData(at date: Date) -> Bool {
        arrivals.contains { $0.isStale(comparedTo: date) }
    }

    func hasStalePositionData(at date: Date) -> Bool {
        positions.contains { $0.isStale(comparedTo: date) }
    }

    nonisolated static func automaticRefreshInterval(
        base: TimeInterval,
        consecutiveFailures: Int
    ) -> TimeInterval {
        let exponent = min(max(consecutiveFailures, 0), 3)
        return min(base * pow(2, Double(exponent)), maximumAutomaticRefreshInterval)
    }

    private var currentAutomaticRefreshInterval: TimeInterval {
        Self.automaticRefreshInterval(
            base: refreshInterval,
            consecutiveFailures: consecutiveTransitFailures
        )
    }

    private func resumeAutomaticRefreshSession(now: Date) {
        automaticRefreshSessionDeadline = now.addingTimeInterval(refreshSessionDuration)
        isAutomaticRefreshPaused = false
    }

    private func fetchPositions(for lineNames: [String]) async -> [PositionLineResult] {
        let client = transitClient
        return await withTaskGroup(of: PositionLineResult.self) { group in
            for lineName in lineNames {
                group.addTask {
                    do {
                        return PositionLineResult(
                            lineName: lineName,
                            result: .success(try await client.positions(on: lineName))
                        )
                    } catch is CancellationError {
                        return PositionLineResult(lineName: lineName, result: .failure(.workerUnavailable))
                    } catch let error as TransitAPIError {
                        return PositionLineResult(lineName: lineName, result: .failure(error))
                    } catch {
                        return PositionLineResult(lineName: lineName, result: .failure(.workerUnavailable))
                    }
                }
            }

            var results: [PositionLineResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
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
        positions = []
        lastTrains = []
        positionsByLine = [:]
        arrivalMessage = nil
        positionMessage = lineRouteLoadMessage
        lastTrainMessage = nil
        lastSuccessfulArrivalRefreshAt = nil
        lastSuccessfulPositionRefreshAt = nil
        lastSuccessfulLastTrainRefreshAt = nil
        lastTrainServiceDayInfo = nil
        isUsingRetainedLastTrainData = false
        lastTransitRequest = nil
        consecutiveTransitFailures = 0
        automaticRefreshSessionDeadline = nil
        isAutomaticRefreshPaused = false
        lastTrainCacheKey = nil
    }

    private static let timetableLines: Set<String> = [
        "1호선", "2호선", "3호선", "4호선", "5호선", "6호선", "7호선", "8호선", "9호선",
    ]
}

private struct PositionLineResult: Sendable {
    let lineName: String
    let result: Result<[TrainPosition], TransitAPIError>
}
