import CoreLocation
import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel = HomeViewModel()
    @State private var isStationPickerPresented = false
    @State private var showsAllPositions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    stationHeader
                    statusMessages
                    positionSection
                    arrivalSection
                    lastTrainSection
                    dataNotice
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarHidden(true)
            .refreshable {
                viewModel.refreshLocation()
                await viewModel.refreshAll()
            }
            .sheet(isPresented: $isStationPickerPresented) {
                stationPicker
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                viewModel.start()
            }
            .task(id: automaticRefreshID) {
                guard scenePhase == .active else { return }
                await viewModel.runAutomaticArrivalRefresh()
            }
            .task(id: lastTrainRefreshID) {
                guard scenePhase == .active else { return }
                await viewModel.refreshLastTrains()
            }
            .onChange(of: viewModel.selectedStation?.id) {
                showsAllPositions = false
            }
        }
    }

    private var stationHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            stationHeaderControls

            if let station = viewModel.selectedStation {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(station.lineNames, id: \.self) { lineName in
                            LineBadge(lineName: lineName)
                        }

                        if let nearby = viewModel.nearbyStations.first(where: { $0.station.id == station.id }) {
                            Label(distanceText(nearby.distance), systemImage: "location.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(Color.secondary.opacity(0.08), in: Capsule())
                        }
                    }
                }
            } else {
                Button("가까운 역 또는 이용할 역 선택") {
                    isStationPickerPresented = true
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(18)
        .cardSurface()
    }

    @ViewBuilder
    private var stationHeaderControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                stationSelectionButton
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        liveStatus
                        Text(lastUpdatedText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    refreshButton
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                stationSelectionButton
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    liveStatus
                    Text(lastUpdatedText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                refreshButton
            }
        }
    }

    private var stationSelectionButton: some View {
        Button {
            isStationPickerPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("GoHome")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text(selectedStationTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("선택 역, \(selectedStationTitle), 변경")
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshAll() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .rotationEffect(viewModel.isLoadingAnyData ? .degrees(360) : .zero)
                .animation(
                    viewModel.isLoadingAnyData
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: viewModel.isLoadingAnyData
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedStation == nil || viewModel.isLoadingAnyData)
        .accessibilityLabel(viewModel.isLoadingAnyData ? "교통 정보 갱신 중" : "교통 정보 새로고침")
    }

    @ViewBuilder
    private var statusMessages: some View {
        if viewModel.isShowingLastSuccessfulData ||
            viewModel.isShowingLastSuccessfulPositionData ||
            viewModel.isShowingLastSuccessfulLastTrainData {
            StatusBanner(
                title: "마지막 정상 데이터를 표시 중입니다",
                detail: "새 요청에 실패했습니다. 연결이 회복되면 자동으로 갱신합니다.",
                systemImage: "clock.arrow.circlepath",
                color: .orange
            )
        } else if viewModel.hasStaleArrivalData || viewModel.hasStalePositionData {
            StatusBanner(
                title: "수신이 지연되고 있습니다",
                detail: "2분 이상 지난 정보가 포함되어 있습니다.",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        }

        if let message = combinedTransitMessage {
            StatusBanner(
                title: "일부 정보를 불러오지 못했습니다",
                detail: message,
                systemImage: "wifi.exclamationmark",
                color: .orange
            )
        }
    }

    @ViewBuilder
    private var positionSection: some View {
        SectionHeading(
            eyebrow: "STATION-BASED LIVE POSITION",
            title: "집으로 가는 열차",
            trailing: positionCountText
        )

        if viewModel.selectedStation == nil {
            EmptyTransitCard(
                title: "역을 먼저 선택해 주세요",
                detail: "가까운 역이나 자주 이용하는 역을 선택하면 접근 중인 열차를 보여드립니다.",
                systemImage: "tram"
            )
        } else if viewModel.displayedPositions.isEmpty {
            EmptyTransitCard(
                title: viewModel.isLoadingPositions ? "열차 위치 확인 중" : "접근 중인 열차가 없습니다",
                detail: viewModel.isLoadingPositions
                    ? "현재 역과 운행 상태를 불러오고 있습니다."
                    : "잠시 후 아래로 당겨 다시 확인해 주세요.",
                systemImage: viewModel.isLoadingPositions ? "arrow.triangle.2.circlepath" : "tram"
            )
        } else {
            ForEach(visiblePositions) { position in
                TrainRouteCard(
                    position: position,
                    selectedStationName: viewModel.selectedStation?.name ?? "선택 역"
                )
            }

            if viewModel.displayedPositions.count > Self.collapsedPositionLimit {
                Button {
                    withAnimation(.snappy) {
                        showsAllPositions.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(showsAllPositions ? "가까운 열차만 보기" : "나머지 열차 \(hiddenPositionCount)대 보기")
                        Image(systemName: showsAllPositions ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var arrivalSection: some View {
        SectionHeading(
            eyebrow: "NEXT ARRIVALS",
            title: "곧 도착하는 열차",
            trailing: viewModel.arrivals.isEmpty ? nil : "\(viewModel.arrivals.count)대"
        )

        if viewModel.arrivals.isEmpty {
            EmptyTransitCard(
                title: viewModel.isLoadingArrivals ? "도착정보 확인 중" : "도착정보가 없습니다",
                detail: viewModel.isLoadingArrivals
                    ? "서울시 실시간 정보를 불러오고 있습니다."
                    : "선택 역을 변경하거나 잠시 후 다시 확인해 주세요.",
                systemImage: viewModel.isLoadingArrivals ? "arrow.triangle.2.circlepath" : "clock"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.arrivals.enumerated()), id: \.element.id) { index, arrival in
                    ArrivalRow(arrival: arrival)
                    if index < viewModel.arrivals.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.horizontal, 16)
            .cardSurface()
        }
    }

    private var dataNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("열차의 GPS 위치가 아닙니다", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("서울시가 제공한 현재 역과 진입·도착·출발 상태를 기준으로 계산합니다. 원천 데이터 수신·가공 과정에서 지연될 수 있습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let receivedAt = latestReceivedAt {
                Text("데이터 기준 \(receivedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.isPositionListLimited {
                Text("각 노선·방향별 가까운 열차를 최대 3대까지 표시합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var lastTrainSection: some View {
        SectionHeading(
            eyebrow: "SCHEDULED LAST TRAINS",
            title: "막차 예정 시간",
            trailing: lastTrainDayTitle
        )

        HStack(spacing: 12) {
            Label("영업일", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Picker("막차 영업일", selection: $viewModel.lastTrainDaySelection) {
                ForEach(LastTrainDaySelection.allCases) { selection in
                    Text(selection.title).tag(selection)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .cardSurface()

        if let message = viewModel.lastTrainMessage {
            StatusBanner(
                title: viewModel.lastTrains.isEmpty ? "막차 시간표를 확인하지 못했습니다" : "시간표 확인이 필요합니다",
                detail: message,
                systemImage: "calendar.badge.exclamationmark",
                color: .orange
            )
        }

        if viewModel.lastTrains.isEmpty {
            EmptyTransitCard(
                title: viewModel.isLoadingLastTrains ? "막차 시간표 확인 중" : "표시할 막차 시간표가 없습니다",
                detail: viewModel.isLoadingLastTrains
                    ? "선택 역의 방향·종착역별 마지막 열차를 찾고 있습니다."
                    : "현재 서울교통공사 1~9호선 예정 시간표를 제공합니다.",
                systemImage: viewModel.isLoadingLastTrains ? "arrow.triangle.2.circlepath" : "moon.stars"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.lastTrains.enumerated()), id: \.element.id) { index, train in
                    LastTrainRow(train: train)
                    if index < viewModel.lastTrains.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.horizontal, 16)
            .cardSurface()

            Text("예정 시간표이며 실제 운행·도착 시각과 다를 수 있습니다. 토요일과 일·공휴일은 원천 API의 동일한 주말 시간표를 사용합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var stationPicker: some View {
        NavigationStack {
            List {
                Section("내 위치") {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(authorizationText)
                                .font(.subheadline.weight(.semibold))
                            if let locationMessage = viewModel.locationMessage {
                                Text(locationMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("다시 찾기") {
                            viewModel.refreshLocation()
                        }
                    }
                }

                Section("가까운 역") {
                    if viewModel.nearbyStations.isEmpty {
                        Text(locationUnavailable ? "검색으로 이용할 역을 선택해 주세요." : "위치를 확인하고 있습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.nearbyStations) { nearby in
                            stationButton(
                                nearby.station,
                                detail: "\(nearby.station.lineNames.joined(separator: " · ")) · \(distanceText(nearby.distance))"
                            )
                        }
                    }
                }

                Section {
                    TextField("역명 또는 노선명", text: $viewModel.stationSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !trimmedSearchText.isEmpty {
                        if viewModel.stationSearchResults.isEmpty {
                            Text("일치하는 지원 역이 없습니다.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.stationSearchResults) { station in
                                stationButton(station, detail: station.lineNames.joined(separator: " · "))
                            }
                        }
                    }
                } header: {
                    Text("역 직접 찾기")
                } footer: {
                    Text("위치 권한이 없거나 서울 밖에 있어도 서울시 실시간 API 지원 역을 선택할 수 있습니다.")
                }
            }
            .navigationTitle("역 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        isStationPickerPresented = false
                    }
                }
            }
        }
    }

    private func stationButton(_ station: Station, detail: String) -> some View {
        Button {
            viewModel.select(station)
            isStationPickerPresented = false
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(station.name)역")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selectedStation?.id == station.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var liveStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(liveStatusColor)
                .frame(width: 7, height: 7)
            Text(liveStatusText)
                .font(.caption2.bold())
        }
        .foregroundStyle(liveStatusColor)
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .background(liveStatusColor.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var liveStatusText: String {
        if viewModel.isLoadingTransitData { return "갱신 중" }
        if viewModel.hasStaleArrivalData || viewModel.hasStalePositionData { return "지연" }
        if viewModel.lastSuccessfulArrivalRefreshAt != nil || viewModel.lastSuccessfulPositionRefreshAt != nil {
            return "LIVE"
        }
        return "대기"
    }

    private var liveStatusColor: Color {
        switch liveStatusText {
        case "LIVE": return .green
        case "갱신 중": return .blue
        case "지연": return .orange
        default: return .secondary
        }
    }

    private var selectedStationTitle: String {
        viewModel.selectedStation.map { "\($0.name)역" } ?? "역 선택"
    }

    private var lastUpdatedText: String {
        guard let date = lastSuccessfulRefreshAt else { return "갱신 전" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var lastSuccessfulRefreshAt: Date? {
        [viewModel.lastSuccessfulArrivalRefreshAt, viewModel.lastSuccessfulPositionRefreshAt]
            .compactMap { $0 }
            .max()
    }

    private var lastTrainDayTitle: String? {
        guard let info = viewModel.lastTrainServiceDayInfo else { return nil }
        if let holidayName = info.holidayName {
            return "\(info.type.title) · \(holidayName)"
        }
        return info.type.title
    }

    private var latestReceivedAt: Date? {
        [viewModel.latestArrivalReceivedAt, viewModel.latestPositionReceivedAt]
            .compactMap { $0 }
            .max()
    }

    private var combinedTransitMessage: String? {
        [viewModel.arrivalMessage, viewModel.positionMessage]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty
    }

    private var positionCountText: String? {
        viewModel.displayedPositions.isEmpty ? nil : "\(viewModel.displayedPositions.count)대 접근 중"
    }

    private var visiblePositions: [TrainPosition] {
        showsAllPositions
            ? viewModel.displayedPositions
            : Array(viewModel.displayedPositions.prefix(Self.collapsedPositionLimit))
    }

    private var hiddenPositionCount: Int {
        max(0, viewModel.displayedPositions.count - Self.collapsedPositionLimit)
    }

    private var trimmedSearchText: String {
        viewModel.stationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var authorizationText: String {
        switch viewModel.authorizationStatus {
        case .notDetermined: return "권한 확인 전"
        case .restricted: return "위치 사용 제한"
        case .denied: return "위치 권한 거부됨"
        case .authorizedAlways, .authorizedWhenInUse:
            return viewModel.accuracyAuthorization == .reducedAccuracy
                ? "위치 사용 허용됨 · 대략적"
                : "위치 사용 허용됨 · 정확함"
        @unknown default: return "알 수 없는 상태"
        }
    }

    private func distanceText(_ distance: CLLocationDistance) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded()))m"
        }
        return String(format: "%.1fkm", distance / 1_000)
    }

    private var automaticRefreshID: String {
        let lifecycle = scenePhase == .active ? "active" : "inactive"
        return "\(lifecycle):\(viewModel.selectedStation?.id ?? "no-station")"
    }

    private var lastTrainRefreshID: String {
        "\(automaticRefreshID):\(viewModel.lastTrainDaySelection.rawValue)"
    }

    private var locationUnavailable: Bool {
        viewModel.authorizationStatus == .denied ||
            viewModel.authorizationStatus == .restricted ||
            viewModel.locationMessage != nil
    }

    private static let collapsedPositionLimit = 4
}

private struct TrainRouteCard: View {
    let position: TrainPosition
    let selectedStationName: String

    private var lineColor: Color { SubwayLineStyle.color(for: position.lineName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LineBadge(lineName: position.lineName)
                Text(position.directionText)
                    .font(.subheadline.weight(.semibold))
                if position.serviceType != .regular {
                    TransitBadge(text: position.serviceType.rawValue, color: .blue)
                }
                if position.isLastTrain {
                    TransitBadge(text: "막차", color: .red)
                }
                Spacer(minLength: 8)
                Text(remainingStopsText)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(lineColor)
            }

            HStack(alignment: .top, spacing: 12) {
                RouteStrip(color: lineColor, isAtSelectedStation: position.remainingStationCount == 0)
                    .frame(width: 20, height: 76)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(position.currentStation) \(position.status.rawValue)")
                            .font(.headline)
                        Text("\(position.destination) · 열차 \(position.trainNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text("\(selectedStationName)역")
                            .font(.subheadline.weight(.semibold))
                        if position.remainingStationCount == 0 {
                            TransitBadge(text: "현재 이 역", color: lineColor)
                        }
                    }
                }
            }
        }
        .padding(18)
        .cardSurface(accent: lineColor)
        .accessibilityElement(children: .combine)
    }

    private var remainingStopsText: String {
        guard let count = position.remainingStationCount else { return "거리 계산 중" }
        return count == 0 ? "지금 이 역" : "\(count)역 전"
    }
}

private struct RouteStrip: View {
    let color: Color
    let isAtSelectedStation: Bool

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            ZStack {
                Capsule()
                    .fill(color.opacity(0.22))
                    .frame(width: 3, height: max(0, geometry.size.height - 18))
                    .position(x: centerX, y: geometry.size.height / 2)

                Circle()
                    .fill(color)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.background, lineWidth: 3))
                    .position(x: centerX, y: 7)

                Circle()
                    .fill(isAtSelectedStation ? color : Color(uiColor: .systemBackground))
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(color, lineWidth: 2.5))
                    .position(x: centerX, y: geometry.size.height - 7)

                Image(systemName: "tram.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(color, in: Circle())
                    .position(x: centerX, y: isAtSelectedStation ? geometry.size.height - 7 : geometry.size.height * 0.42)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ArrivalRow: View {
    let arrival: TrainArrival

    private var lineColor: Color { SubwayLineStyle.color(for: arrival.lineName) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(lineName: arrival.lineName, compact: true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(destinationLabel)
                        .font(.body.weight(.semibold))
                    if arrival.isExpress {
                        TransitBadge(text: "급행", color: .blue)
                    }
                    if arrival.isLastTrain {
                        TransitBadge(text: "막차", color: .red)
                    }
                }
                Text("\(arrival.direction) · \(arrival.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(etaPrimaryText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(etaColor)
                if let secondary = etaSecondaryText {
                    Text(secondary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var etaPrimaryText: String {
        guard let seconds = arrival.remainingSeconds else { return arrival.status.rawValue }
        if seconds <= 0 { return arrival.status.rawValue }
        return "\(seconds / 60)분"
    }

    private var etaSecondaryText: String? {
        guard let seconds = arrival.remainingSeconds, seconds > 0 else { return nil }
        return "\(seconds % 60)초"
    }

    private var etaColor: Color {
        guard let seconds = arrival.remainingSeconds, seconds > 0 else { return .red }
        return seconds <= 120 ? .orange : lineColor
    }

    private var destinationLabel: String {
        arrival.destination.hasSuffix("행")
            ? arrival.destination
            : "\(arrival.destination)행"
    }
}

private struct LastTrainRow: View {
    let train: LastTrain
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var lineColor: Color { SubwayLineStyle.color(for: train.lineName) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleBody
            } else {
                regularBody
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var regularBody: some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(lineName: train.lineName, compact: true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(destinationText)
                        .font(.body.weight(.semibold))
                    if train.isExpress {
                        TransitBadge(text: "급행", color: .blue)
                    }
                }
                Text("\(train.direction.title) · 예정 시간표 · 열차 \(train.trainNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(departureTimeText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(lineColor)
                Text(remainingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibleBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LineBadge(lineName: train.lineName, compact: true)
                Text(destinationText)
                    .font(.body.weight(.semibold))
                if train.isExpress {
                    TransitBadge(text: "급행", color: .blue)
                }
            }

            Text("\(train.direction.title) · 예정 시간표 · 열차 \(train.trainNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(departureTimeText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(lineColor)
                Spacer(minLength: 8)
                Text(remainingText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var departureTimeText: String {
        let calendar = TransitServiceClock.seoulCalendar
        let nextDay = !calendar.isDate(train.departureAt, inSameDayAs: train.serviceDate)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "a h:mm"
        let time = formatter.string(from: train.departureAt)
        return nextDay ? "\(time) (+1일)" : time
    }

    private var destinationText: String {
        train.destination.hasSuffix("행")
            ? train.destination
            : "\(train.destination)행"
    }

    private var remainingText: String {
        let remaining = train.remainingTime(at: Date())
        guard remaining > 0 else { return "운행 종료" }
        let minutes = Int(remaining / 60)
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분 남음"
        }
        return "\(max(1, minutes))분 남음"
    }
}

private struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let trailing: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    titleBlock
                    if let trailing {
                        Text(trailing)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .bottom) {
                    titleBlock
                    Spacer()
                    if let trailing {
                        Text(trailing)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(.caption2.bold())
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
        }
    }
}

private struct LineBadge: View {
    let lineName: String
    var compact = false

    private var color: Color { SubwayLineStyle.color(for: lineName) }

    var body: some View {
        Text(compact ? SubwayLineStyle.shortName(for: lineName) : lineName)
            .font((compact ? Font.caption2 : Font.caption).bold())
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 7 : 9)
            .frame(minWidth: compact ? 30 : 0, minHeight: compact ? 30 : 28)
            .background(color, in: Capsule())
            .accessibilityLabel(lineName)
    }
}

private struct TransitBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct StatusBanner: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyTransitCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

private enum SubwayLineStyle {
    static func color(for lineName: String) -> Color {
        switch lineName {
        case "1호선": return Color(red: 0.00, green: 0.32, blue: 0.64)
        case "2호선": return Color(red: 0.00, green: 0.58, blue: 0.27)
        case "3호선": return Color(red: 0.95, green: 0.42, blue: 0.08)
        case "4호선": return Color(red: 0.00, green: 0.65, blue: 0.82)
        case "5호선": return Color(red: 0.56, green: 0.25, blue: 0.69)
        case "6호선": return Color(red: 0.64, green: 0.38, blue: 0.16)
        case "7호선": return Color(red: 0.45, green: 0.51, blue: 0.10)
        case "8호선": return Color(red: 0.86, green: 0.12, blue: 0.42)
        case "9호선": return Color(red: 0.72, green: 0.58, blue: 0.19)
        case "수인분당선": return Color(red: 0.93, green: 0.72, blue: 0.08)
        case "신분당선": return Color(red: 0.77, green: 0.08, blue: 0.12)
        case "경의중앙선": return Color(red: 0.15, green: 0.69, blue: 0.55)
        case "경춘선": return Color(red: 0.10, green: 0.69, blue: 0.45)
        case "공항철도": return Color(red: 0.00, green: 0.47, blue: 0.69)
        case "우이신설선": return Color(red: 0.72, green: 0.78, blue: 0.18)
        case "서해선": return Color(red: 0.45, green: 0.72, blue: 0.20)
        case "경강선": return Color(red: 0.00, green: 0.48, blue: 0.67)
        case "GTX-A": return Color(red: 0.46, green: 0.20, blue: 0.65)
        default: return .indigo
        }
    }

    static func shortName(for lineName: String) -> String {
        lineName.replacingOccurrences(of: "호선", with: "")
    }
}

private extension View {
    func cardSurface(accent: Color? = nil) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .leading) {
                if let accent {
                    Capsule()
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.vertical, 14)
                        .padding(.leading, 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    HomeView()
}
