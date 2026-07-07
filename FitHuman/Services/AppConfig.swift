import Foundation

enum AppConfig {
    static let backendBaseURL: URL = {
        let configuredValue = Bundle.main
            .object(forInfoDictionaryKey: "FITHUMAN_API_BASE_URL") as? String
        let value = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        let resolvedValue = value?.isEmpty == false
            ? value!
            : "http://127.0.0.1:8000/api/v1/"
        #else
        guard let resolvedValue = value,
              resolvedValue.isEmpty == false,
              resolvedValue.hasPrefix("https://"),
              resolvedValue.contains("your-backend-host") == false,
              resolvedValue.contains("localhost") == false,
              resolvedValue.contains("127.0.0.1") == false else {
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
}
