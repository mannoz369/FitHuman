import Foundation

struct WaterLog: Codable {
    let day: String
    let currentIntakeML: Double
    let dailyGoalML: Double
    let lastIntakeAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case day
        case currentIntakeML = "current_intake_ml"
        case dailyGoalML = "daily_goal_ml"
        case lastIntakeAt = "last_intake_at"
        case updatedAt = "updated_at"
    }
}

struct WaterHistoryDay: Codable, Identifiable {
    let day: String
    let currentIntakeML: Double?
    let dailyGoalML: Double
    let lastIntakeAt: Date?
    let updatedAt: Date?

    var id: String { day }

    var progress: Double? {
        guard let currentIntakeML, dailyGoalML > 0 else {
            return nil
        }

        return min(currentIntakeML / dailyGoalML, 1.0)
    }

    enum CodingKeys: String, CodingKey {
        case day
        case currentIntakeML = "current_intake_ml"
        case dailyGoalML = "daily_goal_ml"
        case lastIntakeAt = "last_intake_at"
        case updatedAt = "updated_at"
    }
}

struct WaterHistory: Codable {
    let days: [WaterHistoryDay]
    let averageIntakeML: Double
    let totalIntakeML: Double
    let loggedDayCount: Int

    enum CodingKeys: String, CodingKey {
        case days
        case averageIntakeML = "average_intake_ml"
        case totalIntakeML = "total_intake_ml"
        case loggedDayCount = "logged_day_count"
    }
}

struct AddWaterRequest: Encodable {
    let amountML: Double

    enum CodingKeys: String, CodingKey {
        case amountML = "amount_ml"
    }
}

struct UpdateWaterGoalRequest: Encodable {
    let dailyGoalML: Double

    enum CodingKeys: String, CodingKey {
        case dailyGoalML = "daily_goal_ml"
    }
}
