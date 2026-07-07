import Foundation

enum AppConfig {
    // iOS Simulator can reach a backend running on your Mac at 127.0.0.1.
    // For a physical device, replace this with your LAN or production HTTPS URL.
    static let backendBaseURL = URL(string: "http://127.0.0.1:8000/api/v1/")!
}
