import SwiftUI

struct LiveView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var preferences: StationPreferences

    @State private var selectedLine: String?
    @State private var selectedDirection: String?
    @State private var selectedPosition: TrainPosition?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                DataTrustBanner(viewModel: viewModel)
                filters

                Label("역 기준 위치 · GPS 아님", systemImage: "info.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TransitPalette.slate)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(TransitPalette.steel.opacity(0.75), in: Capsule())

                if filteredPositions.isEmpty {
                    TransitEmptyState(
                        title: viewModel.isLoadingPositions ? "열차 위치 확인 중" : "표시할 접근 열차가 없습니다",
                        detail: viewModel.selectedStation == nil ? "역 탭에서 이용할 역을 먼저 선택해 주세요." : "노선이나 방향 필터를 바꾸거나 잠시 후 새로고침해 주세요.",
                        systemImage: viewModel.isLoadingPositions ? "arrow.triangle.2.circlepath" : "tram"
                    )
                } else {
                    ForEach(filteredPositions) { position in
                        Button {
                            selectedPosition = position
                        } label: {
                            LiveRouteCard(
                                position: position,
                                selectedStationName: viewModel.selectedStation?.name ?? "선택 역"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .transitPageBackground()
        .navigationTitle("실시간")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TransitRefreshButton(isLoading: viewModel.isLoadingTransitData) {
                    Task { await viewModel.refreshArrivals() }
                }
            }
        }
        .refreshable { await viewModel.refreshArrivals() }
        .onAppear { normalizeFilters() }
        .onChange(of: viewModel.selectedStation?.id) { normalizeFilters() }
        .onChange(of: selectedLine) { selectedDirection = nil }
        .sheet(item: $selectedPosition) { position in
            if let station = viewModel.selectedStation {
                TrainDetailSheet(
                    position: position,
                    selectedStation: station,
                    preferences: preferences
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedStation.map { "\($0.name)역" } ?? "역 선택 필요")
                    .font(.title2.bold())
                Text("접근 중인 열차의 현재 역과 상태")
                    .font(.subheadline)
                    .foregroundStyle(TransitPalette.slate)
            }
            Spacer()
            if viewModel.isLoadingPositions {
                ProgressView().tint(TransitPalette.cobalt)
            } else {
                TransitStatusPill(
                    text: viewModel.hasStalePositionData ? "지연" : "LIVE",
                    color: viewModel.hasStalePositionData ? TransitPalette.warning : TransitPalette.liveTeal,
                    systemImage: nil
                )
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.selectedStation?.lineNames ?? [], id: \.self) { lineName in
                        filterChip(
                            title: lineName,
                            isSelected: selectedLine == lineName,
                            color: SubwayLineStyle.color(for: lineName)
                        ) { selectedLine = lineName }
                    }
                }
            }

            if !directions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(
                            title: "전체 방향",
                            isSelected: selectedDirection == nil,
                            color: TransitPalette.cobalt
                        ) { selectedDirection = nil }
                        ForEach(directions, id: \.self) { direction in
                            filterChip(
                                title: direction,
                                isSelected: selectedDirection == direction,
                                color: TransitPalette.cobalt
                            ) { selectedDirection = direction }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(
        title: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : TransitPalette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(isSelected ? color : TransitPalette.ivory, in: Capsule())
                .overlay { Capsule().stroke(color.opacity(isSelected ? 0 : 0.22), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private var filteredPositions: [TrainPosition] {
        viewModel.displayedPositions.filter { position in
            (selectedLine == nil || position.lineName == selectedLine) &&
                (selectedDirection == nil || position.directionText == selectedDirection)
        }
    }

    private var directions: [String] {
        Array(Set(viewModel.displayedPositions.filter {
            selectedLine == nil || $0.lineName == selectedLine
        }.map(\.directionText))).sorted()
    }

    private func normalizeFilters() {
        let lines = viewModel.selectedStation?.lineNames ?? []
        if let selectedLine, lines.contains(selectedLine) { return }
        selectedLine = lines.first
        selectedDirection = nil
    }
}

private struct LiveRouteCard: View {
    let position: TrainPosition
    let selectedStationName: String

    private var color: Color { SubwayLineStyle.color(for: position.lineName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LineBadge(lineName: position.lineName)
                Text(position.directionText)
                    .font(.subheadline.weight(.semibold))
                if position.serviceType != .regular {
                    TransitStatusPill(text: position.serviceType.rawValue, color: color, systemImage: nil)
                }
                if position.isLastTrain {
                    TransitStatusPill(text: "막차", color: TransitPalette.warning, systemImage: "moon.stars.fill")
                }
                Spacer(minLength: 8)
                Text(remainingText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            }

            MiniRouteStrip(position: position, selectedStationName: selectedStationName)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(position.trainNumber) 열차")
                        .font(.headline)
                    Text("\(position.destination)행 · \(position.currentStation) \(position.status.rawValue)")
                        .font(.caption)
                        .foregroundStyle(TransitPalette.slate)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(TransitPalette.slate)
            }
        }
        .padding(18)
        .transitCard(tone: .blue, accent: color)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("두 번 탭하여 열차 상세 보기")
    }

    private var remainingText: String {
        guard let count = position.remainingStationCount else { return "거리 계산 중" }
        return count == 0 ? "현재 이 역" : "\(count)역 전"
    }
}
