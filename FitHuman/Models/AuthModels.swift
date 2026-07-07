import Foundation

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let name: String?
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: UserAccount

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}

struct UserAccount: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let profile: UserFitnessProfile?
    let currentStreak: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case profile
        case currentStreak = "current_streak"
        case createdAt = "created_at"
    }
}
