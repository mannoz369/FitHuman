import SwiftUI

struct AuthView: View {
    @ObservedObject var session: AuthSessionViewModel

    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(isRegistering ? "Create Account" : "Welcome Back")
                        .font(.largeTitle.bold())
                        .listRowSeparator(.hidden)

                    Text("Sign in to sync your monthly workout plan, progress, streak, and water tracking.")
                        .foregroundColor(.secondary)
                        .listRowSeparator(.hidden)
                }

                Section {
                    Picker("Mode", selection: $isRegistering) {
                        Text("Login").tag(false)
                        Text("Register").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if isRegistering {
                        nameField
                    }

                    emailField
                    passwordField
                }

                if let validationMessage {
                    Text(validationMessage)
                        .foregroundColor(.red)
                }

                if let authError = session.authErrorMessage {
                    Text(authError)
                        .foregroundColor(.red)
                }

                Button {
                    submit()
                } label: {
                    if session.isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(isRegistering ? "Create Account" : "Login")
                    }
                }
                .disabled(session.isWorking)
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .navigationTitle("")
        }
    }

    @ViewBuilder
    private var nameField: some View {
        #if os(iOS)
        TextField("Name", text: $name)
            .textContentType(.name)
        #else
        TextField("Name", text: $name)
        #endif
    }

    @ViewBuilder
    private var emailField: some View {
        #if os(iOS)
        TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.emailAddress)
        #else
        TextField("Email", text: $email)
        #endif
    }

    @ViewBuilder
    private var passwordField: some View {
        #if os(iOS)
        SecureField("Password", text: $password)
            .textContentType(isRegistering ? .newPassword : .password)
        #else
        SecureField("Password", text: $password)
        #endif
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedEmail.contains("@") else {
            validationMessage = "Enter a valid email."
            return
        }

        guard password.count >= 8 else {
            validationMessage = "Password must be at least 8 characters."
            return
        }

        validationMessage = nil

        Task {
            if isRegistering {
                await session.register(
                    email: trimmedEmail,
                    password: password,
                    name: trimmedName.isEmpty ? nil : trimmedName
                )
            } else {
                await session.login(email: trimmedEmail, password: password)
            }
        }
    }
}
