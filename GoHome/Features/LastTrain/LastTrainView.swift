import SwiftUI
import UserNotifications

struct LastTrainView: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var reminders = LastTrainReminderStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                DataTrustBanner(viewModel: viewModel)
                daySelector
                hero
                scheduleList
                notice
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .transitPageBackground()
        .navigationTitle("막차")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TransitRefreshButton(isLoading: viewModel.isLoadingLastTrains) {
                    Task { await viewModel.refreshLastTrains(force: true) }
                }
            }
        }
        .refreshable { await viewModel.refreshLastTrains(force: true) }
        .alert("막차 알림", isPresented: reminderAlertBinding) {
            Button("확인", role: .cancel) { reminders.message = nil }
        } message: {
            Text(reminders.message ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.selectedStation.map { "\($0.name)역" } ?? "역 선택 필요")
                .font(.title2.bold())
            Text("방향과 종착역별 마지막 예정 열차")
                .font(.subheadline)
                .foregroundStyle(TransitPalette.slate)
        }
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LastTrainDaySelection.allCases) { selection in
                    Button {
                        viewModel.lastTrainDaySelection = selection
                    } label: {
                        Text(selection.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(viewModel.lastTrainDaySelection == selection ? Color.white : TransitPalette.ink)
                            .padding(.horizontal, 15)
                            .frame(minHeight: 40)
                            .background(
                                viewModel.lastTrainDaySelection == selection ? TransitPalette.cobalt : TransitPalette.ivory,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel("막차 영업일")
    }

    @ViewBuilder
    private var hero: some View {
        if let train = nextTrain {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("막차까지")
                            .font(.headline)
                        LastTrainCountdownText(departureAt: train.departureAt)
                    }
                    Spacer()
                    LineBadge(lineName: train.lineName)
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(departureTime(train.departureAt))
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        Text("\(destinationText(train)) · \(train.direction.title)")
                            .font(.headline)
                    }
                    Spacer()
                    Button {
                        reminders.toggle(train)
                    } label: {
                        Label(
                            reminders.isScheduled(train) ? "알림 해제" : "알림 설정",
                            systemImage: reminders.isScheduled(train) ? "bell.slash.fill" : "bell.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TransitPalette.cobalt)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(TransitPalette.cardBlue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .transitCard(tone: .sand, accent: TransitPalette.warning)
        } else {
            TransitEmptyState(
                title: viewModel.isLoadingLastTrains ? "막차 시간표 확인 중" : "표시할 막차가 없습니다",
                detail: viewModel.selectedStation == nil ? "역 탭에서 이용할 역을 선택해 주세요." : "현재 서울교통공사 1~9호선의 예정 시간표를 제공합니다.",
                systemImage: viewModel.isLoadingLastTrains ? "arrow.triangle.2.circlepath" : "moon.stars"
            )
        }
    }

    @ViewBuilder
    private var scheduleList: some View {
        if !viewModel.lastTrains.isEmpty {
            TransitSectionHeading(
                eyebrow: "SCHEDULE",
                title: "방향별 막차",
                trailing: serviceDayTitle
            )

            VStack(spacing: 0) {
                ForEach(Array(viewModel.lastTrains.enumerated()), id: \.element.id) { index, train in
                    LastTrainScheduleRow(
                        train: train,
                        isScheduled: reminders.isScheduled(train),
                        onToggleReminder: { reminders.toggle(train) }
                    )
                    if index < viewModel.lastTrains.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, 16)
            .transitCard(tone: .neutral)
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("예정 시간표", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
            Text("실제 운행·도착 시각과 다를 수 있습니다. 알림은 기기에서만 예약되며 서버로 역이나 시간 정보를 보내지 않습니다.")
                .font(.caption)
                .foregroundStyle(TransitPalette.slate)
            if let message = viewModel.lastTrainMessage {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TransitPalette.warning)
            }
        }
        .padding(16)
        .transitCard(tone: .mint)
    }

    private var nextTrain: LastTrain? {
        let now = Date()
        return viewModel.lastTrains
            .filter { $0.departureAt > now }
            .sorted { $0.departureAt < $1.departureAt }
            .first ?? viewModel.lastTrains.sorted { $0.departureAt < $1.departureAt }.first
    }

    private var serviceDayTitle: String? {
        guard let info = viewModel.lastTrainServiceDayInfo else { return nil }
        return info.holidayName.map { "\(info.type.title) · \($0)" } ?? info.type.title
    }

    private func departureTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func destinationText(_ train: LastTrain) -> String {
        train.destination.hasSuffix("행") ? train.destination : "\(train.destination)행"
    }

    private var reminderAlertBinding: Binding<Bool> {
        Binding(
            get: { reminders.message != nil },
            set: { if !$0 { reminders.message = nil } }
        )
    }
}

private struct LastTrainCountdownText: View {
    let departureAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minutes = max(0, Int(departureAt.timeIntervalSince(context.date) / 60))
            Text(minutes > 0 ? "\(minutes)분" : "운행 종료")
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(minutes <= 20 ? TransitPalette.warning : TransitPalette.transitGreen)
                .contentTransition(.numericText(value: Double(minutes)))
                .animation(.snappy, value: minutes)
        }
    }
}

private struct LastTrainScheduleRow: View {
    let train: LastTrain
    let isScheduled: Bool
    let onToggleReminder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(lineName: train.lineName, compact: true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(destinationText)
                        .font(.body.weight(.semibold))
                    if train.isExpress {
                        TransitStatusPill(text: "급행", color: TransitPalette.cobalt, systemImage: nil)
                    }
                }
                Text("\(train.direction.title) · 열차 \(train.trainNumber)")
                    .font(.caption)
                    .foregroundStyle(TransitPalette.slate)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(train.departureAt.formatted(date: .omitted, time: .shortened))
                    .font(.title3.bold().monospacedDigit())
                Button(action: onToggleReminder) {
                    Label(isScheduled ? "해제" : "알림", systemImage: isScheduled ? "bell.slash" : "bell")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TransitPalette.cobalt)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var destinationText: String {
        train.destination.hasSuffix("행") ? train.destination : "\(train.destination)행"
    }
}

@MainActor
private final class LastTrainReminderStore: ObservableObject {
    @Published private(set) var scheduledIDs: Set<String>
    @Published var message: String?

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let storageKey = "gohome.last-train-reminders"

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        scheduledIDs = Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    func isScheduled(_ train: LastTrain) -> Bool {
        scheduledIDs.contains(identifier(for: train))
    }

    func toggle(_ train: LastTrain) {
        let id = identifier(for: train)
        if scheduledIDs.contains(id) {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            scheduledIDs.remove(id)
            persist()
            message = "막차 알림을 해제했습니다."
            return
        }

        Task { await schedule(train, identifier: id) }
    }

    private func schedule(_ train: LastTrain, identifier: String) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                message = "알림 권한이 꺼져 있습니다. iPhone 설정에서 GoHome 알림을 허용해 주세요."
                return
            }

            let preferredDate = train.departureAt.addingTimeInterval(-20 * 60)
            let fallbackDate = train.departureAt.addingTimeInterval(-5 * 60)
            let usesPreferredDate = preferredDate > Date()
            let notificationDate = usesPreferredDate ? preferredDate : fallbackDate
            guard notificationDate > Date() else {
                message = "이 막차는 알림을 예약하기에 너무 임박했습니다."
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "막차 출발 \(usesPreferredDate ? 20 : 5)분 전"
            content.body = "\(train.lineName) \(train.destination)행 막차가 \(train.departureAt.formatted(date: .omitted, time: .shortened))에 출발할 예정입니다."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: notificationDate.timeIntervalSinceNow,
                repeats: false
            )
            try await center.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            )
            scheduledIDs.insert(identifier)
            persist()
            message = usesPreferredDate ? "막차 20분 전 알림을 설정했습니다." : "막차 5분 전 알림을 설정했습니다."
        } catch {
            message = "막차 알림을 설정하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }

    private func identifier(for train: LastTrain) -> String {
        "gohome.last-train.\(train.id)"
    }

    private func persist() {
        defaults.set(Array(scheduledIDs).sorted(), forKey: storageKey)
    }
}
