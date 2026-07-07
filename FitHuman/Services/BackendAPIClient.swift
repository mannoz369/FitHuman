import Foundation

final class BackendAPIClient {
    var accessToken: String?

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = AppConfig.backendBaseURL, session: URLSession = .fithumanAPI) {
        self.baseURL = baseURL
        self.session = session
    }

    func register(email: String, password: String, name: String?) async throws -> AuthResponse {
        try await request(
            "auth/register",
            method: "POST",
            body: RegisterRequest(email: email, password: password, name: name),
            requiresAuth: false
        )
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await request(
            "auth/login",
            method: "POST",
            body: LoginRequest(email: email, password: password),
            requiresAuth: false
        )
    }

    func getCurrentUser() async throws -> UserAccount {
        try await request("users/me")
    }

    func getCurrentWorkoutPlan() async throws -> CurrentWorkoutPlanResponse {
        try await request("workout-plans/current")
    }

    func generateWorkoutPlan(profile: UserFitnessProfile) async throws -> WorkoutPlan {
        try await request("workout-plans/generate", method: "POST", body: profile)
    }

    func continueCurrentWorkoutPlan() async throws -> WorkoutPlan {
        try await request("workout-plans/current/continue", method: "POST")
    }

    func getWorkoutProgress(planId: String? = nil) async throws -> WorkoutProgress? {
        let queryItems = planId.map { [URLQueryItem(name: "plan_id", value: $0)] } ?? []
        return try await request("workouts/progress", queryItems: queryItems)
    }

    func saveWorkoutProgress(planId: String, currentExerciseIndex: Int, isWorkoutComplete: Bool) async throws -> WorkoutProgress {
        let payload = WorkoutProgressRequest(
            planId: planId,
            currentExerciseIndex: currentExerciseIndex,
            isWorkoutComplete: isWorkoutComplete
        )
        return try await request("workouts/progress", method: "PUT", body: payload)
    }

    func completeWorkout(
        planId: String?,
        dayName: String?,
        durationSeconds: Int?,
        setCount: Int?,
        exercises: [Exercise]
    ) async throws -> CompleteWorkoutResponse {
        let payload = CompleteWorkoutRequest(
            planId: planId,
            dayName: dayName,
            durationSeconds: durationSeconds,
            setCount: setCount,
            exercises: exercises
        )
        return try await request("workouts/complete", method: "POST", body: payload)
    }

    func getWorkoutCaloriesSummary() async throws -> WorkoutCaloriesSummary {
        try await request("workouts/sessions")
    }

    func getTodayWater() async throws -> WaterLog {
        try await request("water/today")
    }

    func getWaterHistory(days: Int = 7) async throws -> WaterHistory {
        try await request("water/history", queryItems: [URLQueryItem(name: "days", value: "\(days)")])
    }

    func addWater(amountML: Double) async throws -> WaterLog {
        try await request("water/intake", method: "POST", body: AddWaterRequest(amountML: amountML))
    }

    func updateWaterGoal(dailyGoalML: Double) async throws -> WaterLog {
        try await request("water/goal", method: "PATCH", body: UpdateWaterGoalRequest(dailyGoalML: dailyGoalML))
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) async throws -> Response {
        try await request(path, method: method, queryItems: queryItems, bodyData: nil, requiresAuth: requiresAuth)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: RequestBody,
        requiresAuth: Bool = true
    ) async throws -> Response {
        let bodyData = try Self.encoder.encode(body)
        return try await request(path, method: method, queryItems: queryItems, bodyData: bodyData, requiresAuth: requiresAuth)
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        requiresAuth: Bool
    ) async throws -> Response {
        guard var components = URLComponents(url: URL(string: path, relativeTo: baseURL)!.absoluteURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.addValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Time-Zone")

        if let bodyData {
            request.httpBody = bodyData
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuth {
            guard let accessToken else {
                throw APIError.missingToken
            }
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let apiError as APIError {
            throw apiError
        } catch {
            if Self.isCancellation(error) {
                throw CancellationError()
            }

            throw APIError.network(url: url, message: Self.networkMessage(from: error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.server(statusCode: httpResponse.statusCode, message: Self.errorMessage(from: data))
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch let decodingError as DecodingError {
            throw APIError.decoding(Self.decodingMessage(from: decodingError))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            for formatter in [
                isoFormatterWithFractionalSeconds,
                isoFormatter,
                isoFormatterWithoutTimezoneWithFractionalSeconds,
                isoFormatterWithoutTimezone
            ] {
                if let date = formatter.date(from: string) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithoutTimezoneWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withFractionalSeconds
        ]
        return formatter
    }()

    private static let isoFormatterWithoutTimezone: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        return formatter
    }()

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = json["detail"] else {
            return String(data: data, encoding: .utf8) ?? "Request failed"
        }

        if let message = detail as? String {
            return message
        }

        return "\(detail)"
    }

    private static func decodingMessage(from error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let value = codingPath.map(\.stringValue).joined(separator: ".")
            return value.isEmpty ? "<root>" : value
        }

        switch error {
        case .typeMismatch(let type, let context):
            return "Could not decode \(type) at \(path(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(path(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(path(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Invalid data at \(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func networkMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "\(nsError.localizedDescription) (NSURLErrorDomain \(nsError.code))"
        }

        return error.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingToken
    case network(url: URL, message: String)
    case server(statusCode: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL."
        case .invalidResponse:
            return "Invalid backend response."
        case .missingToken:
            return "Please log in again."
        case .network(let url, let message):
            return "Could not reach \(url.absoluteString): \(message)"
        case .server(let statusCode, let message):
            return "Request failed (\(statusCode)): \(message)"
        case .decoding(let message):
            return message
        }
    }
}

private extension URLSession {
    static let fithumanAPI: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()
}
