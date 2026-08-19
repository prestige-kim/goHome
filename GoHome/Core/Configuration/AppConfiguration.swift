import Foundation

enum AppConfiguration {
    static var seoulAPIKey: String? {
        value(for: "SeoulAPIKey")
    }

    static var publicDataAPIKey: String? {
        value(for: "PublicDataAPIKey")
    }

    private static func value(for key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }

        return trimmed
    }
}
