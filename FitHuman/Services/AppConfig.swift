import Foundation

enum AppConfig {
    private static let deployedBackendBaseURL = "https://fithuman.onrender.com/api/v1/"

    static let backendBaseURL: URL = {
        let configuredValue = Bundle.main
            .object(forInfoDictionaryKey: "FITHUMAN_API_BASE_URL") as? String
        let value = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        let resolvedValue = Self.isUsableBackendURL(value)
            ? value!
            : Self.deployedBackendBaseURL
        #else
        guard let resolvedValue = value,
              resolvedValue.isEmpty == false,
              resolvedValue.hasPrefix("https://"),
              Self.isLocalOrPlaceholder(resolvedValue) == false else {
            preconditionFailure(
                "Set FITHUMAN_API_BASE_URL to the production HTTPS backend URL before archiving."
            )
        }
        #endif

        guard let url = URL(string: resolvedValue) else {
            preconditionFailure("Invalid FITHUMAN_API_BASE_URL: \(resolvedValue)")
        }

        return url
    }()

    private static func isUsableBackendURL(_ value: String?) -> Bool {
        guard let value, value.isEmpty == false else {
            return false
        }

        return isLocalOrPlaceholder(value) == false
    }

    private static func isLocalOrPlaceholder(_ value: String) -> Bool {
        value.contains("your-backend-host")
            || value.contains("localhost")
            || value.contains("127.0.0.1")
    }
}
