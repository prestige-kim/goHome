import Foundation

enum LastTrainServiceDay: String, CaseIterable, Codable, Sendable {
    case weekday
    case saturday
    case sundayHoliday = "sunday_holiday"

    var title: String {
        switch self {
        case .weekday: "평일"
        case .saturday: "토요일"
        case .sundayHoliday: "일·공휴일"
        }
    }
}

enum LastTrainDaySelection: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case weekday
    case saturday
    case sundayHoliday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "오늘"
        case .weekday: "평일"
        case .saturday: "토요일"
        case .sundayHoliday: "일·공휴일"
        }
    }

    var fixedServiceDay: LastTrainServiceDay? {
        switch self {
        case .automatic: nil
        case .weekday: .weekday
        case .saturday: .saturday
        case .sundayHoliday: .sundayHoliday
        }
    }
}

struct LastTrainServiceDayInfo: Equatable, Sendable {
    let date: Date
    let type: LastTrainServiceDay
    let holidayName: String?
    let isHolidayVerified: Bool
}

enum LastTrainDirection: String, CaseIterable, Codable, Sendable {
    case up
    case down
    case inner
    case outer

    var title: String {
        switch self {
        case .up: "상행"
        case .down: "하행"
        case .inner: "내선"
        case .outer: "외선"
        }
    }
}

struct LastTrain: Identifiable, Equatable, Sendable {
    let id: String
    let lineName: String
    let direction: LastTrainDirection
    let destination: String
    let trainNumber: String
    let departureAt: Date
    let serviceDate: Date
    let serviceDay: LastTrainServiceDay
    let isExpress: Bool

    func remainingTime(at date: Date) -> TimeInterval {
        departureAt.timeIntervalSince(date)
    }
}

enum TransitServiceClock {
    nonisolated static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }

    nonisolated static func serviceDate(
        containing date: Date,
        cutoffHour: Int = 4,
        calendar: Calendar = seoulCalendar
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        return hour < cutoffHour
            ? calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            : startOfDay
    }

    nonisolated static func departureDate(
        time: String,
        serviceDate: Date,
        cutoffHour: Int = 4,
        calendar: Calendar = seoulCalendar
    ) -> Date? {
        let components = time.split(separator: ":").map(String.init)
        let values: [Int]
        if components.count == 3 {
            values = components.compactMap(Int.init)
        } else {
            let compact = time.filter(\.isNumber)
            guard compact.count == 6 else { return nil }
            values = stride(from: 0, to: 6, by: 2).compactMap { index in
                let start = compact.index(compact.startIndex, offsetBy: index)
                let end = compact.index(start, offsetBy: 2)
                return Int(compact[start..<end])
            }
        }

        guard values.count == 3 else { return nil }
        var hour = values[0]
        let minute = values[1]
        let second = values[2]
        guard (0...29).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            return nil
        }

        if hour < cutoffHour {
            hour += 24
        }
        let dayOffset = hour / 24
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: serviceDate) else {
            return nil
        }
        return calendar.date(
            bySettingHour: hour % 24,
            minute: minute,
            second: second,
            of: day
        )
    }

    nonisolated static func isoDateString(
        from date: Date,
        calendar: Calendar = seoulCalendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    nonisolated static func localServiceDay(
        for date: Date,
        calendar: Calendar = seoulCalendar
    ) -> LastTrainServiceDay {
        switch calendar.component(.weekday, from: date) {
        case 1: .sundayHoliday
        case 7: .saturday
        default: .weekday
        }
    }
}
