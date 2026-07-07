import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthSessionViewModel: ObservableObject {
    @Published var currentUser: UserAccount?
    @Published var isCheckingSession = true
    @Published var isWorking = false
    @Published var authErrorMessage: String?

    let apiClient: BackendAPIClient

    var isAuthenticated: Bool {
        currentUser != nil
    }

    init(apiClient: BackendAPIClient = BackendAPIClient()) {
        self.apiClient = apiClient

        if let token = KeychainTokenStore.load() {
            apiClient.accessToken = token
            Task {
                await refreshCurrentUser()
            }
        } else {
            isCheckingSession = false
        }
    }

    func refreshCurrentUser() async {
        do {
            currentUser = try await apiClient.getCurrentUser()
            authErrorMessage = nil
        } catch {
            guard !Self.isCancellation(error) else {
                isCheckingSession = false
                return
            }
            KeychainTokenStore.delete()
            apiClient.accessToken = nil
            currentUser = nil
            authErrorMessage = nil
        }

        isCheckingSession = false
    }

    func login(email: String, password: String) async {
        await authenticate {
            try await apiClient.login(email: email, password: password)
        }
    }

    func register(email: String, password: String, name: String?) async {
        await authenticate {
            try await apiClient.register(email: email, password: password, name: name)
        }
    }

    func logout() {
        KeychainTokenStore.delete()
        apiClient.accessToken = nil
        currentUser = nil
        authErrorMessage = nil
    }

    private func authenticate(_ request: () async throws -> AuthResponse) async {
        isWorking = true
        authErrorMessage = nil

        do {
            let response = try await request()
            try KeychainTokenStore.save(response.accessToken)
            apiClient.accessToken = response.accessToken
            currentUser = response.user
        } catch {
            guard !Self.isCancellation(error) else {
                authErrorMessage = nil
                isWorking = false
                return
            }
            authErrorMessage = error.localizedDescription
        }

        isWorking = false
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
