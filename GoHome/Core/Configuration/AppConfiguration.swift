import Foundation

enum AppConfiguration {
    static var transitProxyBaseURL: URL? {
        guard let rawValue = value(for: "TransitProxyBaseURL") else {
            return nil
        }
        return URL(string: rawValue)
    }

    static var transitProxyClientToken: String? {
        value(for: "TransitProxyClientToken")
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
