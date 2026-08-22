import CoreLocation
import SwiftUI

enum TransitTab: Hashable {
    case home
    case live
    case lastTrain
    case stations
}

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var preferences = StationPreferences()
    @State private var selectedTab: TransitTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView(
                    viewModel: viewModel,
                    preferences: preferences,
                    onOpenLive: { selectedTab = .live },
                    onOpenLastTrain: { selectedTab = .lastTrain },
                    onOpenStations: { selectedTab = .stations }
                )
            }
            .tabItem { Label("홈", systemImage: "house.fill") }
            .tag(TransitTab.home)

            NavigationStack {
                LiveView(viewModel: viewModel, preferences: preferences)
            }
            .tabItem { Label("실시간", systemImage: "waveform.path.ecg") }
            .tag(TransitTab.live)

            NavigationStack {
                LastTrainView(viewModel: viewModel)
            }
            .tabItem { Label("막차", systemImage: "moon.stars.fill") }
            .tag(TransitTab.lastTrain)

            NavigationStack {
                StationsView(
                    viewModel: viewModel,
                    preferences: preferences,
                    onSelectStation: { station in
                        viewModel.select(station)
                        preferences.recordRecent(station)
                        selectedTab = .home
                    }
                )
            }
            .tabItem { Label("역", systemImage: "mappin.and.ellipse") }
            .tag(TransitTab.stations)
        }
        .tint(TransitPalette.cobalt)
        .toolbarBackground(TransitPalette.steel, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.light)
        .task { viewModel.start() }
        .task(id: automaticRefreshID) {
            guard scenePhase == .active else { return }
            await viewModel.runAutomaticArrivalRefresh()
        }
        .task(id: lastTrainRefreshID) {
            guard scenePhase == .active else { return }
            await viewModel.refreshLastTrains()
        }
        .onChange(of: viewModel.selectedStation?.id) {
            if let station = viewModel.selectedStation {
                preferences.recordRecent(station)
            }
        }
    }

    private var automaticRefreshID: String {
        let lifecycle = scenePhase == .active ? "active" : "inactive"
        return "\(lifecycle):\(viewModel.selectedStation?.id ?? "no-station")"
    }

    private var lastTrainRefreshID: String {
        "\(automaticRefreshID):\(viewModel.lastTrainDaySelection.rawValue)"
    }
}

private struct HomeDashboardView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var preferences: StationPreferences
    let onOpenLive: () -> Void
    let onOpenLastTrain: () -> Void
    let onOpenStations: () -> Void

    @State private var selectedLine: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                DataTrustBanner(viewModel: viewModel)
                trainHero
                quickActions
                arrivalPreview
                dataStatusCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .transitPageBackground()
        .navigationBarHidden(true)
        .refreshable {
            viewModel.refreshLocation()
            await viewModel.refreshAll()
        }
        .onChange(of: viewModel.selectedStation?.id) { selectedLine = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpenStations) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GoHome")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TransitPalette.slate)
                        HStack(spacing: 7) {
                            Text(selectedStationTitle)
                                .font(.largeTitle.bold())
                                .foregroundStyle(TransitPalette.ink)
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(TransitPalette.slate)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("선택 역 \(selectedStationTitle), 변경")

                TransitIconButton(
                    systemImage: "arrow.left.arrow.right",
                    accessibilityLabel: "역 변경",
                    action: onOpenStations
                )

                TransitIconButton(
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    accessibilityLabel: isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                    color: isFavorite ? TransitPalette.favorite : TransitPalette.ink
                ) {
                    if let station = viewModel.selectedStation {
                        preferences.toggleFavorite(station)
                    }
                }
            }

            HStack(spacing: 8) {
                if let station = viewModel.selectedStation {
                    ForEach(station.lineNames, id: \.self) { LineBadge(lineName: $0) }
                }
                liveStatus
                Spacer(minLength: 6)

                Menu {
                    Button("전체 노선") { selectedLine = nil }
                    if let station = viewModel.selectedStation {
                        ForEach(station.lineNames, id: \.self) { lineName in
                            Button(lineName) { selectedLine = lineName }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TransitPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(TransitPalette.ivory, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("노선 필터")

                TransitRefreshButton(isLoading: viewModel.isLoadingAnyData) {
                    Task { await viewModel.refreshAll() }
                }
            }
        }
    }

    @ViewBuilder
    private var trainHero: some View {
        TransitSectionHeading(eyebrow: "NEXT TRAIN", title: "지금 탈 열차", trailing: selectedLine)

        if let position = visiblePositions.first {
            Button(action: onOpenLive) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        LineBadge(lineName: position.lineName)
                        Text(position.directionText)
                            .font(.subheadline.weight(.semibold))
                        if position.serviceType != .regular {
                            TransitStatusPill(text: position.serviceType.rawValue, color: SubwayLineStyle.color(for: position.lineName), systemImage: nil)
                        }
                        Spacer()
                        Text(position.remainingStationCount.map { $0 == 0 ? "현재 이 역" : "\($0)역 전" } ?? "거리 계산 중")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(SubwayLineStyle.color(for: position.lineName))
                    }

                    ArrivalCountdownText(arrival: matchingArrival(for: position), fallback: position.status.rawValue)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(position.destination) 방면")
                                .font(.title3.bold())
                            Text("\(position.currentStation) \(position.status.rawValue) · 열차 \(position.trainNumber)")
                                .font(.caption)
                                .foregroundStyle(TransitPalette.slate)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(TransitPalette.slate)
                    }

                    MiniRouteStrip(position: position, selectedStationName: viewModel.selectedStation?.name ?? "선택 역", horizontal: true)
                }
                .padding(20)
                .transitCard(tone: .blue, accent: SubwayLineStyle.color(for: position.lineName))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if let arrival = visibleArrivals.first {
            Button(action: onOpenLive) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        LineBadge(lineName: arrival.lineName)
                        Text(arrival.direction)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    ArrivalCountdownText(arrival: arrival, fallback: arrival.status.rawValue)
                    Text("\(destinationText(for: arrival)) · \(arrival.message)")
                        .font(.headline)
                    Label("열차 위치를 확인하려면 실시간 탭을 여세요", systemImage: "tram.fill")
                        .font(.caption)
                        .foregroundStyle(TransitPalette.slate)
                }
                .padding(20)
                .transitCard(tone: .blue, accent: SubwayLineStyle.color(for: arrival.lineName))
            }
            .buttonStyle(.plain)
        } else {
            TransitEmptyState(
                title: viewModel.selectedStation == nil ? "역을 먼저 선택해 주세요" : "접근 중인 열차가 없습니다",
                detail: viewModel.isLoadingTransitData ? "현재 역과 도착정보를 확인하고 있습니다." : "잠시 후 새로고침하거나 다른 역을 선택해 주세요.",
                systemImage: viewModel.isLoadingTransitData ? "arrow.triangle.2.circlepath" : "tram"
            )
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            QuickActionButton(title: "실시간", systemImage: "tram.fill", tone: .blue, color: TransitPalette.cobalt, action: onOpenLive)
            QuickActionButton(title: "막차", systemImage: "moon.stars.fill", tone: .sand, color: TransitPalette.warning, action: onOpenLastTrain)
            QuickActionButton(title: "역 변경", systemImage: "arrow.left.arrow.right", tone: .lilac, color: Color.purple, action: onOpenStations)
            QuickActionButton(
                title: isFavorite ? "저장됨" : "즐겨찾기",
                systemImage: isFavorite ? "heart.fill" : "heart",
                tone: .peach,
                color: TransitPalette.favorite
            ) {
                if let station = viewModel.selectedStation { preferences.toggleFavorite(station) }
            }
        }
    }

    @ViewBuilder
    private var arrivalPreview: some View {
        TransitSectionHeading(eyebrow: "ARRIVALS", title: "다음 도착", trailing: visibleArrivals.isEmpty ? nil : "\(visibleArrivals.count)대")

        if visibleArrivals.isEmpty {
            TransitEmptyState(
                title: viewModel.isLoadingArrivals ? "도착정보 확인 중" : "도착정보가 없습니다",
                detail: "선택 역의 다음 열차를 불러오면 여기에 요약합니다.",
                systemImage: viewModel.isLoadingArrivals ? "arrow.triangle.2.circlepath" : "clock"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visibleArrivals.prefix(3).enumerated()), id: \.element.id) { index, arrival in
                    ArrivalPreviewRow(arrival: arrival)
                    if index < min(3, visibleArrivals.count) - 1 {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 16)
            .transitCard(tone: .neutral)
        }
    }

    private var dataStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("데이터 상태", systemImage: "checkmark.shield.fill")
                .font(.headline)
            statusRow(title: "도착정보", date: viewModel.lastSuccessfulArrivalRefreshAt, isLoading: viewModel.isLoadingArrivals, hasIssue: viewModel.arrivalMessage != nil || viewModel.hasStaleArrivalData)
            statusRow(title: "열차 위치", date: viewModel.lastSuccessfulPositionRefreshAt, isLoading: viewModel.isLoadingPositions, hasIssue: viewModel.positionMessage != nil || viewModel.hasStalePositionData)
            statusRow(title: "막차 시간표", date: viewModel.lastSuccessfulLastTrainRefreshAt, isLoading: viewModel.isLoadingLastTrains, hasIssue: viewModel.lastTrainMessage != nil)
            Label("열차 위치는 GPS가 아니라 현재 역과 운행 상태를 기준으로 표시합니다.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(TransitPalette.slate)
        }
        .padding(18)
        .transitCard(tone: .mint)
    }

    private func statusRow(title: String, date: Date?, isLoading: Bool, hasIssue: Bool) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(isLoading ? "갱신 중" : date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "갱신 전")
                .font(.caption.monospacedDigit())
                .foregroundStyle(TransitPalette.slate)
            Circle()
                .fill(hasIssue ? TransitPalette.warning : (date == nil ? TransitPalette.slate : TransitPalette.liveTeal))
                .frame(width: 8, height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var visiblePositions: [TrainPosition] {
        viewModel.displayedPositions.filter { selectedLine == nil || $0.lineName == selectedLine }
    }

    private var visibleArrivals: [TrainArrival] {
        viewModel.arrivals.filter { selectedLine == nil || $0.lineName == selectedLine }
    }

    private func matchingArrival(for position: TrainPosition) -> TrainArrival? {
        visibleArrivals.first { arrival in
            arrival.lineName == position.lineName &&
                (arrival.destination == position.destination || arrival.direction.contains(position.directionText))
        } ?? visibleArrivals.first { $0.lineName == position.lineName }
    }

    private func destinationText(for arrival: TrainArrival) -> String {
        arrival.destination.hasSuffix("행") ? arrival.destination : "\(arrival.destination)행"
    }

    private var selectedStationTitle: String {
        viewModel.selectedStation.map { "\($0.name)역" } ?? "역 선택"
    }

    private var isFavorite: Bool {
        viewModel.selectedStation.map(preferences.isFavorite) ?? false
    }

    private var liveStatus: some View {
        TransitStatusPill(text: liveStatusText, color: liveStatusColor, systemImage: nil)
    }

    private var liveStatusText: String {
        if viewModel.isLoadingTransitData { return "갱신 중" }
        if viewModel.hasStaleArrivalData || viewModel.hasStalePositionData { return "지연" }
        if viewModel.lastSuccessfulArrivalRefreshAt != nil || viewModel.lastSuccessfulPositionRefreshAt != nil {
            return "LIVE · \(lastUpdatedText)"
        }
        return "대기"
    }

    private var liveStatusColor: Color {
        switch liveStatusText {
        case let text where text.hasPrefix("LIVE"): TransitPalette.liveTeal
        case "갱신 중": TransitPalette.cobalt
        case "지연": TransitPalette.warning
        default: TransitPalette.slate
        }
    }

    private var lastUpdatedText: String {
        let latest = [viewModel.lastSuccessfulArrivalRefreshAt, viewModel.lastSuccessfulPositionRefreshAt]
            .compactMap { $0 }
            .max()
        guard let latest else { return "갱신 전" }
        let seconds = max(0, Int(Date().timeIntervalSince(latest)))
        return seconds < 60 ? "방금 갱신" : "\(seconds / 60)분 전"
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let tone: TransitCardTone
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(color, in: Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TransitPalette.ink)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(minHeight: 66)
            .transitCard(tone: tone)
        }
        .buttonStyle(.plain)
    }
}

private struct ArrivalPreviewRow: View {
    let arrival: TrainArrival

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(lineName: arrival.lineName, compact: true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(destinationText)
                        .font(.body.weight(.semibold))
                    if arrival.isExpress {
                        TransitStatusPill(text: "급행", color: TransitPalette.cobalt, systemImage: nil)
                    }
                }
                Text("\(arrival.direction) · \(arrival.message)")
                    .font(.caption)
                    .foregroundStyle(TransitPalette.slate)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            ArrivalCountdownText(arrival: arrival, fallback: arrival.status.rawValue, font: .title3.bold())
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var destinationText: String {
        arrival.destination.hasSuffix("행") ? arrival.destination : "\(arrival.destination)행"
    }
}
