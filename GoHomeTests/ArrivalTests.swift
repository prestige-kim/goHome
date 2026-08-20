import CoreLocation
import Foundation
import XCTest
@testable import GoHome

final class TrainArrivalFreshnessTests: XCTestCase {
    func testArrivalBecomesStaleAfterTwoMinutes() {
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let arrival = makeArrival(receivedAt: receivedAt)

        XCTAssertFalse(arrival.isStale(comparedTo: receivedAt.addingTimeInterval(120)))
        XCTAssertTrue(arrival.isStale(comparedTo: receivedAt.addingTimeInterval(121)))
    }

    func testArrivalWithoutReceivedDateIsStale() {
        XCTAssertTrue(makeArrival(receivedAt: nil).isStale())
    }
}

final class TransitServiceClockTests: XCTestCase {
    func testEarlyMorningBelongsToPreviousServiceDate() throws {
        let calendar = TransitServiceClock.seoulCalendar
        let earlyMorning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 1, minute: 10))
        )

        let serviceDate = TransitServiceClock.serviceDate(containing: earlyMorning)

        XCTAssertEqual(TransitServiceClock.isoDateString(from: serviceDate), "2026-08-19")
    }

    func testZeroAndTwentyFourHourTimesResolveToNextCalendarDay() throws {
        let calendar = TransitServiceClock.seoulCalendar
        let serviceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let zeroHour = try XCTUnwrap(
            TransitServiceClock.departureDate(time: "00:58:30", serviceDate: serviceDate)
        )
        let twentyFourHour = try XCTUnwrap(
            TransitServiceClock.departureDate(time: "24:58:30", serviceDate: serviceDate)
        )

        XCTAssertEqual(zeroHour, twentyFourHour)
        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: zeroHour),
            DateComponents(day: 21, hour: 0, minute: 58)
        )
    }

    func testCompactBusinessHourTimeIsSupported() throws {
        let calendar = TransitServiceClock.seoulCalendar
        let serviceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let departure = try XCTUnwrap(
            TransitServiceClock.departureDate(time: "245830", serviceDate: serviceDate)
        )

        XCTAssertEqual(calendar.component(.day, from: departure), 21)
        XCTAssertEqual(calendar.component(.hour, from: departure), 0)
        XCTAssertEqual(calendar.component(.minute, from: departure), 58)
    }
}

final class DirectSeoulTransitAPIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testMissingConfigurationIsReportedSeparately() async {
        let client = DirectSeoulTransitAPIClient(baseURL: nil, clientToken: nil)

        await assertTransitError(.missingProxyConfiguration) {
            try await client.arrivals(at: testStation)
        }
    }

    func testPositionResponseMapsStatusDirectionAndServiceFlags() async throws {
        URLProtocolStub.requestHandler = successResponse(
            #"{"errorMessage":{"code":"INFO-000","message":"정상 처리되었습니다."},"realtimePositionList":[{"subwayId":"1002","subwayNm":"2호선","statnId":"1002000202","statnNm":"을지로입구","trainNo":"2259","recptnDt":"2026-08-19 14:48:35","updnLine":"0","statnTid":"1002000211","statnTnm":"성수종착","trainSttus":"3","directAt":"7","lstcarAt":"1"}]}"#
        )

        let positions = try await makeClient().positions(on: "2호선")
        let position = try XCTUnwrap(positions.first)

        XCTAssertEqual(position.lineName, "2호선")
        XCTAssertEqual(position.currentStation, "을지로입구")
        XCTAssertEqual(position.status, .departedPreviousStation)
        XCTAssertEqual(position.direction, .upOrInner)
        XCTAssertEqual(position.directionText, "내선")
        XCTAssertEqual(position.serviceType, .limitedExpress)
        XCTAssertTrue(position.isLastTrain)
        XCTAssertNotNil(position.receivedAt)
        XCTAssertNil(position.remainingStationCount)
    }

    func testPositionResponseKeepsLatestSnapshotPerTrainNumber() async throws {
        URLProtocolStub.requestHandler = successResponse(
            #"{"errorMessage":{"code":"INFO-000","message":"정상 처리되었습니다."},"realtimePositionList":[{"subwayId":"1001","subwayNm":"1호선","statnId":"1001000130","statnNm":"종각","trainNo":"0471","recptnDt":"2026-08-19 16:24:13","updnLine":"1","statnTid":"1001080144","statnTnm":"서동탄","trainSttus":"1","directAt":"0","lstcarAt":"0"},{"subwayId":"1001","subwayNm":"1호선","statnId":"1001000130","statnNm":"종각","trainNo":"0471","recptnDt":"2026-08-19 16:26:21","updnLine":"1","statnTid":"1001080144","statnTnm":"서동탄","trainSttus":"2","directAt":"0","lstcarAt":"0"},{"subwayId":"1001","subwayNm":"1호선","statnId":"1001000132","statnNm":"시청","trainNo":"1937","recptnDt":"2026-08-19 16:25:45","updnLine":"1","statnTid":"1001080141","statnTnm":"천안","trainSttus":"1","directAt":"1","lstcarAt":"0"}]}"#
        )

        let positions = try await makeClient().positions(on: "1호선")

        XCTAssertEqual(positions.count, 2)
        let latest = try XCTUnwrap(positions.first { $0.trainNumber == "0471" })
        XCTAssertEqual(latest.status, .departed)
        XCTAssertEqual(latest.currentStation, "종각")
    }

    func testWorkerHTTPFailuresAreClassified() async {
        let cases: [(Int, String, TransitAPIError)] = [
            (401, #"{"error":"unauthorized"}"#, .invalidProxyToken),
            (429, #"{"error":"upstream_rate_limited"}"#, .rateLimitExceeded),
            (500, #"{"error":"missing_seoul_api_key"}"#, .workerConfiguration),
            (502, #"{"error":"upstream_unavailable"}"#, .seoulAPIUnavailable),
            (503, #"{"error":"temporarily_unavailable"}"#, .workerUnavailable),
        ]

        for (statusCode, body, expectedError) in cases {
            URLProtocolStub.requestHandler = { request in
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(body.utf8))
            }

            await assertTransitError(expectedError) {
                try await self.makeClient().arrivals(at: self.testStation)
            }
        }
    }

    func testSeoulAPIErrorAndQuotaMessageAreClassified() async {
        URLProtocolStub.requestHandler = successResponse(
            #"{"errorMessage":{"code":"INFO-100","message":"인증키가 유효하지 않습니다."}}"#
        )

        await assertTransitError(
            .seoulAPI(code: "INFO-100", message: "인증키가 유효하지 않습니다.")
        ) {
            try await self.makeClient().arrivals(at: self.testStation)
        }

        URLProtocolStub.requestHandler = successResponse(
            #"{"RESULT":{"CODE":"ERROR-999","MESSAGE":"일일 호출 한도를 초과했습니다."}}"#
        )

        await assertTransitError(.rateLimitExceeded) {
            try await self.makeClient().arrivals(at: self.testStation)
        }
    }

    func testServiceDayResponseMapsHolidayMetadata() async throws {
        URLProtocolStub.requestHandler = successResponse(
            #"{"date":"2026-08-15","type":"sunday_holiday","holidayName":"광복절"}"#
        )
        let calendar = TransitServiceClock.seoulCalendar
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))
        )

        let result = try await makeClient().serviceDay(for: date)

        XCTAssertEqual(result.type, .sundayHoliday)
        XCTAssertEqual(result.holidayName, "광복절")
        XCTAssertTrue(result.isHolidayVerified)
    }

    func testTimetableResponseKeepsLastDeparturePerDirectionAndDestination() async throws {
        URLProtocolStub.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let direction = components.queryItems?.first { $0.name == "direction" }?.value
            let rowDirection = direction == "up" ? "상행" : "하행"
            let destination = direction == "up" ? "청량리" : "인천"
            let body = #"{"response":{"header":{"resultCode":"00","resultMsg":"NORMAL_CODE"},"body":{"items":{"item":[{"trainno":"100","trainKnd":null,"upbdnbSe":"\#(rowDirection)","lineNm":"1호선","stnNm":"시청","arvlStnNm":"\#(destination)","trainDptreTm":"23:50:00","etrnYn":"N"},{"trainno":"101","trainKnd":null,"upbdnbSe":"\#(rowDirection)","lineNm":"1호선","stnNm":"시청","arvlStnNm":"\#(destination)","trainDptreTm":"24:10:00","etrnYn":"N"}]}}}}"#
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        let calendar = TransitServiceClock.seoulCalendar
        let serviceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )

        let trains = try await makeClient().lastTrains(
            at: testStation,
            serviceDay: .weekday,
            serviceDate: serviceDate
        )

        XCTAssertEqual(trains.count, 2)
        XCTAssertEqual(Set(trains.map(\.direction)), Set([.up, .down]))
        XCTAssertTrue(trains.allSatisfy { $0.trainNumber == "101" })
        XCTAssertTrue(trains.allSatisfy {
            calendar.component(.day, from: $0.departureAt) == 21
        })
    }

    private var testStation: Station {
        Station(
            id: "test",
            name: "시청",
            latitude: 37.566,
            longitude: 126.978,
            lineNames: ["1호선"],
            seoulStationIDs: ["1호선": "1001000132"]
        )
    }

    private func makeClient() -> DirectSeoulTransitAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return DirectSeoulTransitAPIClient(
            baseURL: URL(string: "https://proxy.example"),
            clientToken: "test-token",
            session: URLSession(configuration: configuration)
        )
    }

    private func successResponse(
        _ body: String
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
    }

    private func assertTransitError(
        _ expectedError: TransitAPIError,
        operation: () async throws -> [TrainArrival]
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expectedError)")
        } catch let error as TransitAPIError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
final class LocationServiceTests: XCTestCase {
    func testTransientUnknownErrorDoesNotReplaceSuccessfulLocation() {
        let service = LocationService()
        let manager = CLLocationManager()
        service.locationManager(
            manager,
            didUpdateLocations: [CLLocation(latitude: 37.5665, longitude: 126.9780)]
        )

        let transientError = NSError(
            domain: kCLErrorDomain,
            code: CLError.Code.locationUnknown.rawValue
        )
        service.locationManager(manager, didFailWithError: transientError)

        XCTAssertNotNil(service.location)
        XCTAssertNil(service.errorMessage)
    }
}

@MainActor
final class HomeViewModelArrivalTests: XCTestCase {
    func testRefreshIntervalStaysWithinRequestedRange() {
        XCTAssertTrue((30...45).contains(HomeViewModel.automaticRefreshInterval))
    }

    func testAutomaticRefreshDoesNotDuplicateRecentRequest() async {
        let client = SequencedTransitClient(responses: [.success([]), .success([])])
        let viewModel = makeViewModel(client: client)
        let start = Date(timeIntervalSince1970: 10_000)

        viewModel.select(testStation)
        await viewModel.refreshArrivals(isAutomatic: true, now: start)
        await viewModel.refreshArrivals(isAutomatic: true, now: start.addingTimeInterval(20))
        let requestCountBeforeInterval = await client.requestCount
        XCTAssertEqual(requestCountBeforeInterval, 1)

        await viewModel.refreshArrivals(
            isAutomatic: true,
            now: start.addingTimeInterval(HomeViewModel.automaticRefreshInterval)
        )
        let requestCountAfterInterval = await client.requestCount
        XCTAssertEqual(requestCountAfterInterval, 2)
    }

    func testConcurrentManualAndAutomaticRefreshShareOneRequest() async {
        let client = SequencedTransitClient(
            responses: [.success([])],
            delayNanoseconds: 100_000_000
        )
        let viewModel = makeViewModel(client: client)
        viewModel.select(testStation)

        let firstRequest = Task { await viewModel.refreshArrivals() }
        await Task.yield()
        await viewModel.refreshArrivals(isAutomatic: true)
        await firstRequest.value

        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testCancellingAutomaticRefreshStopsFurtherRequests() async throws {
        let client = SequencedTransitClient(
            responses: Array(repeating: .success([]), count: 10)
        )
        let viewModel = makeViewModel(client: client, automaticRefreshInterval: 0.02)
        viewModel.select(testStation)

        let automaticRefresh = Task { await viewModel.runAutomaticArrivalRefresh() }
        try await Task.sleep(nanoseconds: 55_000_000)
        automaticRefresh.cancel()
        await automaticRefresh.value
        let countAfterCancellation = await client.requestCount

        try await Task.sleep(nanoseconds: 50_000_000)
        let finalCount = await client.requestCount
        XCTAssertGreaterThan(countAfterCancellation, 0)
        XCTAssertEqual(finalCount, countAfterCancellation)
    }

    func testFailedRefreshKeepsLastSuccessfulDataAndMarksItStale() async {
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let arrival = makeArrival(receivedAt: receivedAt)
        let client = SequencedTransitClient(
            responses: [
                .success([arrival]),
                .failure(.workerUnavailable),
            ]
        )
        let viewModel = makeViewModel(client: client)
        viewModel.select(testStation)

        await viewModel.refreshArrivals()
        await viewModel.refreshArrivals()

        XCTAssertEqual(viewModel.arrivals, [arrival])
        XCTAssertTrue(viewModel.isShowingLastSuccessfulData)
        XCTAssertEqual(viewModel.arrivalMessage, TransitAPIError.workerUnavailable.localizedDescription)
        XCTAssertTrue(
            viewModel.hasStaleArrivalData(at: receivedAt.addingTimeInterval(121))
        )
    }

    func testFailedPositionRefreshKeepsLastSuccessfulPosition() async {
        let receivedAt = Date(timeIntervalSince1970: 1_000)
        let position = makePosition(receivedAt: receivedAt)
        let client = SequencedTransitClient(
            responses: [.success([]), .success([])],
            positionResponses: [.success([position]), .failure(.workerUnavailable)]
        )
        let viewModel = makeViewModel(client: client)
        viewModel.select(testStation)

        await viewModel.refreshArrivals()
        await viewModel.refreshArrivals()

        XCTAssertEqual(viewModel.positions.first?.id, position.id)
        XCTAssertEqual(viewModel.positions.first?.remainingStationCount, 1)
        XCTAssertTrue(viewModel.isShowingLastSuccessfulPositionData)
        XCTAssertTrue(viewModel.hasStalePositionData(at: receivedAt.addingTimeInterval(121)))
    }

    private var testStation: Station {
        Station(
            id: "test",
            name: "시청",
            latitude: 37.566,
            longitude: 126.978,
            lineNames: ["1호선"],
            seoulStationIDs: ["1호선": "b"]
        )
    }

    private func makeViewModel(
        client: SequencedTransitClient,
        automaticRefreshInterval: TimeInterval = HomeViewModel.automaticRefreshInterval
    ) -> HomeViewModel {
        HomeViewModel(
            stationRepository: StaticStationRepository(stations: [testStation]),
            lineRouteRepository: StaticLineRouteRepository(
                networks: [
                    LineRouteNetwork(
                        lineName: "1호선",
                        routes: [LineRoute(id: "main", isCircular: false, stationIDs: ["a", "b", "c"])]
                    )
                ]
            ),
            transitClient: client,
            automaticRefreshInterval: automaticRefreshInterval
        )
    }
}

@MainActor
final class HomeViewModelLastTrainTests: XCTestCase {
    func testHolidayFailureFallsBackToCalendarAndStillLoadsTimetable() async throws {
        let calendar = TransitServiceClock.seoulCalendar
        let serviceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let train = makeLastTrain(serviceDate: serviceDate)
        let client = LastTrainTransitClient(
            serviceDayResult: .failure(.holidayConfiguration),
            timetableResults: [.success([train])]
        )
        let viewModel = makeLastTrainViewModel(client: client)
        viewModel.select(lastTrainTestStation)

        await viewModel.refreshLastTrains(now: serviceDate.addingTimeInterval(12 * 60 * 60))

        XCTAssertEqual(viewModel.lastTrains, [train])
        XCTAssertEqual(viewModel.lastTrainServiceDayInfo?.type, .weekday)
        XCTAssertFalse(viewModel.lastTrainServiceDayInfo?.isHolidayVerified ?? true)
        XCTAssertNotNil(viewModel.lastTrainMessage)
        XCTAssertFalse(viewModel.isShowingLastSuccessfulLastTrainData)
    }

    func testTimetableFailureKeepsLastSuccessfulRows() async throws {
        let calendar = TransitServiceClock.seoulCalendar
        let serviceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let train = makeLastTrain(serviceDate: serviceDate)
        let client = LastTrainTransitClient(
            serviceDayResult: .success(
                LastTrainServiceDayInfo(
                    date: serviceDate,
                    type: .weekday,
                    holidayName: nil,
                    isHolidayVerified: true
                )
            ),
            timetableResults: [.success([train]), .failure(.timetableUnavailable)]
        )
        let viewModel = makeLastTrainViewModel(client: client)
        viewModel.select(lastTrainTestStation)

        await viewModel.refreshLastTrains(now: serviceDate.addingTimeInterval(12 * 60 * 60))
        await viewModel.refreshLastTrains(now: serviceDate.addingTimeInterval(13 * 60 * 60))

        XCTAssertEqual(viewModel.lastTrains, [train])
        XCTAssertTrue(viewModel.isShowingLastSuccessfulLastTrainData)
        XCTAssertEqual(viewModel.lastTrainMessage, TransitAPIError.timetableUnavailable.localizedDescription)
    }
}

private actor SequencedTransitClient: TransitAPIClient {
    private var responses: [Result<[TrainArrival], TransitAPIError>]
    private let delayNanoseconds: UInt64
    private var positionResponses: [Result<[TrainPosition], TransitAPIError>]
    private(set) var requestCount = 0

    init(
        responses: [Result<[TrainArrival], TransitAPIError>],
        positionResponses: [Result<[TrainPosition], TransitAPIError>] = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.responses = responses
        self.positionResponses = positionResponses
        self.delayNanoseconds = delayNanoseconds
    }

    func arrivals(at station: Station) async throws -> [TrainArrival] {
        requestCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try responses.removeFirst().get()
    }

    func positions(on lineName: String) async throws -> [TrainPosition] {
        guard !positionResponses.isEmpty else { return [] }
        return try positionResponses.removeFirst().get()
    }
}

private actor LastTrainTransitClient: TransitAPIClient {
    let serviceDayResult: Result<LastTrainServiceDayInfo, TransitAPIError>
    var timetableResults: [Result<[LastTrain], TransitAPIError>]

    init(
        serviceDayResult: Result<LastTrainServiceDayInfo, TransitAPIError>,
        timetableResults: [Result<[LastTrain], TransitAPIError>]
    ) {
        self.serviceDayResult = serviceDayResult
        self.timetableResults = timetableResults
    }

    func arrivals(at station: Station) async throws -> [TrainArrival] { [] }
    func positions(on lineName: String) async throws -> [TrainPosition] { [] }

    func serviceDay(for date: Date) async throws -> LastTrainServiceDayInfo {
        try serviceDayResult.get()
    }

    func lastTrains(
        at station: Station,
        serviceDay: LastTrainServiceDay,
        serviceDate: Date
    ) async throws -> [LastTrain] {
        try timetableResults.removeFirst().get()
    }
}

private struct StaticStationRepository: StationRepository {
    let stations: [Station]

    func loadStations() throws -> [Station] {
        stations
    }
}

private struct StaticLineRouteRepository: LineRouteRepository {
    let networks: [LineRouteNetwork]

    func loadLineRoutes() throws -> [LineRouteNetwork] {
        networks
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeArrival(receivedAt: Date?) -> TrainArrival {
    TrainArrival(
        id: "arrival",
        lineName: "1호선",
        direction: "상행",
        destination: "청량리행",
        remainingSeconds: 120,
        message: "전역 출발",
        status: .departedPreviousStation,
        isExpress: false,
        isLastTrain: false,
        receivedAt: receivedAt
    )
}

private func makePosition(receivedAt: Date?) -> TrainPosition {
    TrainPosition(
        id: "position",
        lineName: "1호선",
        stationID: "a",
        currentStation: "출발역",
        trainNumber: "1001",
        direction: .downOrOuter,
        destinationStationID: "c",
        destination: "종착역",
        status: .departed,
        serviceType: .regular,
        isLastTrain: false,
        receivedAt: receivedAt,
        remainingStationCount: nil
    )
}

private let lastTrainTestStation = Station(
    id: "last-train-test",
    name: "시청",
    latitude: 37.566,
    longitude: 126.978,
    lineNames: ["1호선"]
)

@MainActor
private func makeLastTrainViewModel(client: LastTrainTransitClient) -> HomeViewModel {
    HomeViewModel(
        stationRepository: StaticStationRepository(stations: [lastTrainTestStation]),
        lineRouteRepository: StaticLineRouteRepository(networks: []),
        transitClient: client
    )
}

private func makeLastTrain(serviceDate: Date) -> LastTrain {
    LastTrain(
        id: "last-train",
        lineName: "1호선",
        direction: .up,
        destination: "청량리",
        trainNumber: "101",
        departureAt: TransitServiceClock.departureDate(
            time: "24:10:00",
            serviceDate: serviceDate
        )!,
        serviceDate: serviceDate,
        serviceDay: .weekday,
        isExpress: false
    )
}
