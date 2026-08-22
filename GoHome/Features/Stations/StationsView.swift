import CoreLocation
import SwiftUI

struct StationsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var preferences: StationPreferences
    let onSelectStation: (Station) -> Void

    @State private var detailStation: Station?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                searchField
                locationCard
                nearbySection

                if trimmedSearch.isEmpty {
                    stationSection(
                        eyebrow: "SAVED",
                        title: "즐겨찾기",
                        stations: favoriteStations,
                        emptyTitle: "즐겨찾기한 역이 없습니다"
                    )
                    stationSection(
                        eyebrow: "RECENT",
                        title: "최근 본 역",
                        stations: recentStations,
                        emptyTitle: "최근 선택한 역이 없습니다"
                    )
                } else {
                    stationSection(
                        eyebrow: "SEARCH RESULTS",
                        title: "검색 결과",
                        stations: viewModel.stationSearchResults,
                        emptyTitle: "일치하는 지원 역이 없습니다"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .transitPageBackground()
        .navigationTitle("역")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TransitIconButton(
                    systemImage: "location.fill",
                    accessibilityLabel: "가까운 역 다시 찾기",
                    color: TransitPalette.cobalt,
                    action: viewModel.refreshLocation
                )
            }
        }
        .sheet(item: $detailStation) { station in
            StationDetailSheet(
                station: station,
                isSelected: station.id == viewModel.selectedStation?.id,
                distance: viewModel.nearbyStations.first { $0.station.id == station.id }?.distance,
                preferences: preferences,
                onSelect: { onSelectStation(station) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TransitPalette.slate)
            TextField("역명 또는 노선 검색", text: $viewModel.stationSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !viewModel.stationSearchText.isEmpty {
                Button {
                    viewModel.stationSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TransitPalette.slate)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 52)
        .background(TransitPalette.ivory, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TransitPalette.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private var locationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(TransitPalette.cobalt, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(locationTitle)
                    .font(.subheadline.weight(.semibold))
                if let message = viewModel.locationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(TransitPalette.slate)
                        .lineLimit(3)
                } else {
                    Text("가까운 역을 계산할 때만 기기 위치를 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(TransitPalette.slate)
                }
            }
            Spacer(minLength: 8)
            Button("다시 찾기", action: viewModel.refreshLocation)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(TransitPalette.cobalt)
        }
        .padding(16)
        .transitCard(tone: .mint)
    }

    @ViewBuilder
    private var nearbySection: some View {
        TransitSectionHeading(
            eyebrow: "NEARBY",
            title: "가까운 역",
            trailing: viewModel.nearbyStations.isEmpty ? nil : "\(viewModel.nearbyStations.count)곳"
        )

        if viewModel.nearbyStations.isEmpty {
            TransitEmptyState(
                title: "가까운 역을 확인하고 있습니다",
                detail: "위치를 사용할 수 없어도 위 검색창에서 역을 직접 선택할 수 있습니다.",
                systemImage: "location.magnifyingglass"
            )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.nearbyStations) { nearby in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: nearby.station.id == viewModel.selectedStation?.id ? "checkmark.circle.fill" : "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(TransitPalette.cobalt)
                                Spacer()
                                Button {
                                    preferences.toggleFavorite(nearby.station)
                                } label: {
                                    Image(systemName: preferences.isFavorite(nearby.station) ? "heart.fill" : "heart")
                                        .foregroundStyle(preferences.isFavorite(nearby.station) ? TransitPalette.favorite : TransitPalette.slate)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(preferences.isFavorite(nearby.station) ? "즐겨찾기 해제" : "즐겨찾기")
                            }

                            Button {
                                onSelectStation(nearby.station)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                Text("\(nearby.station.name)역")
                                    .font(.headline)
                                    .foregroundStyle(TransitPalette.ink)
                                Text(distanceText(nearby.distance))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(TransitPalette.slate)
                                HStack(spacing: 5) {
                                    ForEach(nearby.station.lineNames.prefix(3), id: \.self) {
                                        LineBadge(lineName: $0, compact: true)
                                    }
                                }
                            }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("이 역으로 변경")
                        }
                        .padding(16)
                        .frame(width: 176, alignment: .topLeading)
                        .frame(minHeight: 170, alignment: .topLeading)
                        .transitCard(tone: .blue)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func stationSection(
        eyebrow: String,
        title: String,
        stations: [Station],
        emptyTitle: String
    ) -> some View {
        TransitSectionHeading(eyebrow: eyebrow, title: title, trailing: stations.isEmpty ? nil : "\(stations.count)곳")

        if stations.isEmpty {
            TransitEmptyState(
                title: emptyTitle,
                detail: title == "즐겨찾기" ? "자주 이용하는 역의 하트를 눌러 빠르게 전환하세요." : "역을 선택하면 최근 기록에 자동으로 보관합니다.",
                systemImage: title == "즐겨찾기" ? "heart" : "clock.arrow.circlepath"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    StationSelectionRow(
                        station: station,
                        isSelected: station.id == viewModel.selectedStation?.id,
                        isFavorite: preferences.isFavorite(station),
                        onSelect: { onSelectStation(station) },
                        onFavorite: { preferences.toggleFavorite(station) },
                        onDetail: { detailStation = station }
                    )
                    if index < stations.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.horizontal, 14)
            .transitCard(tone: title == "즐겨찾기" ? .mint : .neutral)
        }
    }

    private var favoriteStations: [Station] {
        preferences.stations(for: preferences.favoriteStationIDs, from: viewModel.stations)
    }

    private var recentStations: [Station] {
        preferences.stations(for: preferences.recentStationIDs, from: viewModel.stations)
    }

    private var trimmedSearch: String {
        viewModel.stationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var locationTitle: String {
        switch viewModel.authorizationStatus {
        case .notDetermined: "위치 권한 확인 전"
        case .restricted: "위치 사용 제한"
        case .denied: "위치 권한이 꺼져 있습니다"
        case .authorizedAlways, .authorizedWhenInUse:
            viewModel.accuracyAuthorization == .reducedAccuracy ? "대략적인 위치 사용 중" : "현재 위치 사용 중"
        @unknown default: "위치 상태 확인 필요"
        }
    }

    private func distanceText(_ distance: CLLocationDistance) -> String {
        distance < 1_000 ? "\(Int(distance.rounded()))m" : String(format: "%.1fkm", distance / 1_000)
    }
}

private struct StationSelectionRow: View {
    let station: Station
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onFavorite: () -> Void
    let onDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isSelected ? TransitPalette.liveTeal : TransitPalette.cobalt)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(station.name)역")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TransitPalette.ink)
                        HStack(spacing: 5) {
                            ForEach(station.lineNames.prefix(4), id: \.self) {
                                LineBadge(lineName: $0, compact: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDetail) {
                Image(systemName: "info.circle")
                    .foregroundStyle(TransitPalette.slate)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(station.name)역 상세")

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? TransitPalette.favorite : TransitPalette.slate)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "즐겨찾기 해제" : "즐겨찾기")
        }
        .padding(.vertical, 12)
    }
}

private struct StationDetailSheet: View {
    let station: Station
    let isSelected: Bool
    let distance: CLLocationDistance?
    @ObservedObject var preferences: StationPreferences
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(station.name)역")
                        .font(.largeTitle.bold())
                    if let distance {
                        Label(distance < 1_000 ? "\(Int(distance.rounded()))m" : String(format: "%.1fkm", distance / 1_000), systemImage: "location.fill")
                            .font(.subheadline)
                            .foregroundStyle(TransitPalette.slate)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(station.lineNames, id: \.self) { LineBadge(lineName: $0) }
                }

                Button {
                    preferences.toggleFavorite(station)
                } label: {
                    Label(
                        preferences.isFavorite(station) ? "즐겨찾기 해제" : "즐겨찾기",
                        systemImage: preferences.isFavorite(station) ? "heart.fill" : "heart"
                    )
                    .font(.headline)
                    .foregroundStyle(TransitPalette.favorite)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(TransitPalette.cardPeach, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onSelect()
                    dismiss()
                } label: {
                    Text(isSelected ? "현재 선택된 역" : "이 역으로 변경")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(isSelected ? TransitPalette.slate : TransitPalette.cobalt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSelected)

                Spacer()
            }
            .padding(20)
            .transitPageBackground()
            .navigationTitle("역 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
