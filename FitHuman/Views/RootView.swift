import SwiftUI

struct RootView: View {
    @StateObject private var session = AuthSessionViewModel()

    var body: some View {
        if session.isCheckingSession {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.3)
                Text("Checking session...")
                    .foregroundColor(.secondary)
            }
        } else if session.isAuthenticated {
            MainTabView(session: session)
        } else {
            AuthView(session: session)
        }
    }
}
