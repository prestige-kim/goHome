import CoreLocation
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            List {
                developmentNotice
                locationSection
                nearbyStationSection
                arrivalSection
            }
            .navigationTitle("GoHome")
            .task {
                viewModel.start()
            }
            .refreshable {
                viewModel.refreshLocation()
                await viewModel.refreshArrivals()
            }
        }
    }

    private var developmentNotice: some View {
        Section {
            Label {
                Text("현재 번들에는 서울·시청·종각역만 포함된 개발용 데이터가 들어 있습니다.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "hammer.fill")
            }
            .foregroundStyle(.orange)
        }
    }

    private var locationSection: some View {
        Section("내 위치") {
            HStack {
                Label(authorizationText, systemImage: "location.fill")
                Spacer()
                Button("다시 찾기") {
                    viewModel.refreshLocation()
                }
                .buttonStyle(.borderless)
            }

            if let locationMessage = viewModel.locationMessage {
                Text(locationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var nearbyStationSection: some View {
        Section("가까운 역") {
            if viewModel.nearbyStations.isEmpty {
                ContentUnavailableView(
                    "위치를 기다리는 중",
                    systemImage: "tram",
                    description: Text("위치 권한을 허용하면 가까운 역을 계산합니다.")
                )
            } else {
                ForEach(viewModel.nearbyStations) { nearby in
                    Button {
                        viewModel.select(nearby.station)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(nearby.station.name)
                                    .font(.headline)
                                Text(nearby.station.lineNames.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(distanceText(nearby.distance))
                                .font(.subheadline.monospacedDigit())
                            if viewModel.selectedStation?.id == nearby.station.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var arrivalSection: some View {
        Section {
            if let station = viewModel.selectedStation {
                Button {
                    Task { await viewModel.refreshArrivals() }
                } label: {
                    HStack {
                        Text("\(station.name)역 도착정보 불러오기")
                        Spacer()
                        if viewModel.isLoadingArrivals {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(viewModel.isLoadingArrivals)
            }

            if let arrivalMessage = viewModel.arrivalMessage {
                Text(arrivalMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.arrivals) { arrival in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(arrival.lineName)
                            .font(.headline)
                        Text(arrival.direction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let seconds = arrival.remainingSeconds {
                            Text("\(seconds / 60)분 \(seconds % 60)초")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    Text("\(arrival.destination) · \(arrival.message)")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("실시간 도착")
        } footer: {
            Text("실시간 정보는 원천 데이터 수신·가공 과정에서 지연될 수 있습니다.")
        }
    }

    private var authorizationText: String {
        switch viewModel.authorizationStatus {
        case .notDetermined: return "권한 확인 전"
        case .restricted: return "위치 사용 제한"
        case .denied: return "위치 권한 거부됨"
        case .authorizedAlways, .authorizedWhenInUse: return "위치 사용 허용됨"
        @unknown default: return "알 수 없는 상태"
        }
    }

    private func distanceText(_ distance: CLLocationDistance) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded()))m"
        }
        return String(format: "%.1fkm", distance / 1_000)
    }
}

#Preview {
    HomeView()
}
