import SwiftUI

struct LineBadge: View {
    let lineName: String
    var compact = false

    private var color: Color { SubwayLineStyle.color(for: lineName) }

    var body: some View {
        Text(compact ? SubwayLineStyle.shortName(for: lineName) : lineName)
            .font((compact ? Font.caption2 : Font.caption).bold())
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 8 : 10)
            .frame(minWidth: compact ? 32 : 0, minHeight: compact ? 32 : 30)
            .background(color, in: Capsule())
            .accessibilityLabel(lineName)
    }
}

struct TransitStatusPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(text)
        }
        .font(.caption2.bold())
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(minHeight: 28)
        .background(color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().stroke(color.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TransitSectionHeading: View {
    let eyebrow: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(TransitPalette.slate)
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(TransitPalette.ink)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TransitPalette.slate)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TransitIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var color = TransitPalette.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(TransitPalette.ivory, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TransitPalette.ink.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TransitRefreshButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.body.weight(.semibold))
                .foregroundStyle(TransitPalette.ink)
                .frame(width: 44, height: 44)
                .background(TransitPalette.ivory, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TransitPalette.ink.opacity(0.08), lineWidth: 1)
                }
                .rotationEffect(isLoading ? .degrees(360) : .zero)
                .animation(
                    isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isLoading
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "교통 정보 갱신 중" : "교통 정보 새로고침")
    }
}

struct TransitEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TransitPalette.cobalt)
                .frame(width: 44, height: 44)
                .background(TransitPalette.cobalt.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TransitPalette.slate)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .transitCard(tone: .blue)
        .accessibilityElement(children: .combine)
    }
}

struct ArrivalCountdownText: View {
    let arrival: TrainArrival?
    var fallback: String
    var font: Font = .system(size: 48, weight: .bold, design: .rounded)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = remainingSeconds(at: context.date)
            Text(text(for: seconds))
                .font(font.monospacedDigit())
                .foregroundStyle(TransitPalette.ink)
                .contentTransition(.numericText(value: Double(max(seconds ?? 0, 0))))
                .animation(.snappy, value: seconds)
        }
        .accessibilityLabel(accessibilityText)
    }

    private func remainingSeconds(at date: Date) -> Int? {
        guard let arrival, let original = arrival.remainingSeconds else { return nil }
        let elapsed = Int(date.timeIntervalSince(arrival.receivedAt ?? date))
        return max(0, original - max(0, elapsed))
    }

    private func text(for seconds: Int?) -> String {
        guard let seconds else { return arrival?.status.rawValue ?? fallback }
        guard seconds > 0 else { return "곧 도착" }
        return "\(seconds / 60)분 \(seconds % 60)초"
    }

    private var accessibilityText: String {
        guard let seconds = remainingSeconds(at: Date()) else {
            return arrival?.status.rawValue ?? fallback
        }
        return seconds > 0 ? "\(seconds / 60)분 \(seconds % 60)초 후 도착" : "곧 도착"
    }
}

struct MiniRouteStrip: View {
    let position: TrainPosition
    let selectedStationName: String
    var horizontal = false

    var body: some View {
        if horizontal {
            horizontalBody
        } else {
            verticalBody
        }
    }

    private var color: Color { SubwayLineStyle.color(for: position.lineName) }

    private var verticalBody: some View {
        HStack(alignment: .top, spacing: 14) {
            routeLine
                .frame(width: 24, height: 128)
            VStack(alignment: .leading, spacing: 25) {
                routeLabel(position.currentStation, detail: position.status.rawValue)
                routeLabel(selectedStationName, detail: remainingText)
                routeLabel(position.destination, detail: "종착")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var horizontalBody: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let y = geometry.size.height / 2
                ZStack {
                    Capsule()
                        .fill(TransitPalette.slate.opacity(0.24))
                        .frame(height: 4)
                        .position(x: geometry.size.width / 2, y: y)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width / 2, height: 4)
                        .position(x: geometry.size.width / 4, y: y)
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index < 2 ? color : TransitPalette.steel)
                            .frame(width: index == 1 ? 18 : 12, height: index == 1 ? 18 : 12)
                            .overlay(Circle().stroke(TransitPalette.ivory, lineWidth: 3))
                            .position(x: geometry.size.width * CGFloat(index) / 2, y: y)
                    }
                }
            }
            .frame(height: 26)
            HStack {
                routeLabel(position.currentStation, detail: position.status.rawValue)
                Spacer()
                routeLabel(selectedStationName, detail: remainingText)
                Spacer()
                routeLabel(position.destination, detail: "종착")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var routeLine: some View {
        GeometryReader { geometry in
            let x = geometry.size.width / 2
            ZStack {
                Capsule()
                    .fill(TransitPalette.slate.opacity(0.22))
                    .frame(width: 4, height: geometry.size.height)
                    .position(x: x, y: geometry.size.height / 2)
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: geometry.size.height / 2)
                    .position(x: x, y: geometry.size.height / 4)
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < 2 ? color : TransitPalette.steel)
                        .frame(width: index == 1 ? 18 : 12, height: index == 1 ? 18 : 12)
                        .overlay(Circle().stroke(TransitPalette.ivory, lineWidth: 3))
                        .position(x: x, y: geometry.size.height * CGFloat(index) / 2)
                }
                Image(systemName: "tram.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color, in: Circle())
                    .position(x: x, y: geometry.size.height * 0.28)
                    .symbolEffect(.pulse, value: position.receivedAt)
            }
        }
        .accessibilityHidden(true)
    }

    private func routeLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(TransitPalette.slate)
        }
    }

    private var remainingText: String {
        guard let count = position.remainingStationCount else { return "거리 계산 중" }
        return count == 0 ? "현재 이 역" : "\(count)역 전"
    }
}

struct DataTrustBanner: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        if let state {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state.systemImage)
                    .foregroundStyle(state.color)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(TransitPalette.slate)
                }
                Spacer(minLength: 0)
                TransitStatusPill(text: state.badge, color: state.color, systemImage: nil)
            }
            .padding(14)
            .background(state.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(state.color.opacity(0.24), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var state: TrustState? {
        if viewModel.isAutomaticRefreshPaused {
            return TrustState(
                title: "자동 갱신을 쉬고 있습니다",
                detail: "호출량 보호를 위해 멈췄습니다. 새로고침하면 다시 시작합니다.",
                badge: "일시정지",
                systemImage: "pause.circle.fill",
                color: TransitPalette.warning
            )
        }
        if viewModel.isShowingLastSuccessfulData ||
            viewModel.isShowingLastSuccessfulPositionData ||
            viewModel.isShowingLastSuccessfulLastTrainData {
            return TrustState(
                title: "마지막 정상 데이터를 표시 중",
                detail: "새 요청에 실패했습니다. 연결이 회복되면 자동으로 갱신합니다.",
                badge: "지연",
                systemImage: "clock.arrow.circlepath",
                color: TransitPalette.warning
            )
        }
        if viewModel.hasStaleArrivalData || viewModel.hasStalePositionData {
            return TrustState(
                title: "수신이 지연되고 있습니다",
                detail: "2분 이상 지난 정보가 포함되어 있습니다.",
                badge: "지연",
                systemImage: "exclamationmark.triangle.fill",
                color: TransitPalette.warning
            )
        }
        let messages = [viewModel.arrivalMessage, viewModel.positionMessage]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !messages.isEmpty {
            return TrustState(
                title: "일부 정보를 불러오지 못했습니다",
                detail: messages,
                badge: "확인",
                systemImage: "wifi.exclamationmark",
                color: TransitPalette.warning
            )
        }
        return nil
    }
}

private struct TrustState {
    let title: String
    let detail: String
    let badge: String
    let systemImage: String
    let color: Color
}

struct TrainDetailSheet: View {
    let position: TrainPosition
    let selectedStation: Station
    @ObservedObject var preferences: StationPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        LineBadge(lineName: position.lineName)
                        TransitStatusPill(text: position.serviceType.rawValue, color: SubwayLineStyle.color(for: position.lineName), systemImage: nil)
                        if position.isLastTrain {
                            TransitStatusPill(text: "막차", color: TransitPalette.warning, systemImage: "moon.stars.fill")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(position.trainNumber) 열차")
                            .font(.largeTitle.bold())
                        Text("\(position.destination)행 · \(position.directionText)")
                            .font(.headline)
                            .foregroundStyle(TransitPalette.slate)
                    }

                    MiniRouteStrip(
                        position: position,
                        selectedStationName: selectedStation.name
                    )
                    .padding(18)
                    .transitCard(tone: .blue, accent: SubwayLineStyle.color(for: position.lineName))

                    HStack(spacing: 0) {
                        metric(title: "남은 역", value: remainingStops)
                        Divider().frame(height: 48)
                        metric(title: "현재 상태", value: position.status.rawValue)
                        Divider().frame(height: 48)
                        metric(title: "종착역", value: position.destination)
                    }
                    .padding(16)
                    .transitCard(tone: .neutral)

                    Label("역 기준 위치 · GPS 아님", systemImage: "info.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TransitPalette.slate)

                    if let receivedAt = position.receivedAt {
                        Text("데이터 기준 \(receivedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(TransitPalette.slate)
                    }

                    Button {
                        preferences.toggleFavorite(selectedStation)
                    } label: {
                        Label(
                            preferences.isFavorite(selectedStation) ? "역 즐겨찾기 해제" : "역 즐겨찾기",
                            systemImage: preferences.isFavorite(selectedStation) ? "heart.fill" : "heart"
                        )
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(TransitPalette.cobalt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .transitPageBackground()
            .navigationTitle("열차 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TransitPalette.slate)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var remainingStops: String {
        position.remainingStationCount.map(String.init) ?? "–"
    }
}
