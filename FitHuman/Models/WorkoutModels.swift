import Foundation

struct WeeklyPlanResponse: Codable {
    let weekly_plan: [DailyPlan]
}

struct WorkoutPlan: Codable, Identifiable {
    let id: String
    let weekly_plan: [DailyPlan]
    let profile_snapshot: UserFitnessProfile
    let starts_at: Date
    let ends_at: Date
    let is_active: Bool
    let days_remaining: Int
    let today_plan: DailyPlan?
}

struct CurrentWorkoutPlanResponse: Codable {
    let plan: WorkoutPlan?
    let needs_new_plan: Bool
    let todayProgress: WorkoutProgress?
    let todayIsWorkoutComplete: Bool?
    let currentStreak: Int?

    enum CodingKeys: String, CodingKey {
        case plan
        case needs_new_plan
        case todayProgress = "today_progress"
        case todayIsWorkoutComplete = "today_is_workout_complete"
        case currentStreak = "current_streak"
    }
}

struct DailyPlan: Codable, Identifiable {
    var id: String { day_name }
    let day_name: String
    let is_rest_day: Bool
    let set_count: Int
    let exercises: [Exercise]

    enum CodingKeys: String, CodingKey {
        case day_name, is_rest_day, set_count, exercises
    }

    init(day_name: String, is_rest_day: Bool, set_count: Int, exercises: [Exercise]) {
        self.day_name = day_name
        self.is_rest_day = is_rest_day
        self.set_count = set_count
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day_name = try container.decode(String.self, forKey: .day_name)
        is_rest_day = try container.decode(Bool.self, forKey: .is_rest_day)
        set_count = try container.decodeIfPresent(Int.self, forKey: .set_count) ?? 1
        exercises = try container.decode([Exercise].self, forKey: .exercises)
    }

    var isCardioWorkout: Bool {
        !exercises.isEmpty && exercises.allSatisfy(\.isCardioWorkoutExercise)
    }

    var cardioTargetDescription: String? {
        Exercise.formattedDurationDescription(cardioTargetSeconds)
    }

    private var cardioTargetSeconds: Int {
        exercises
            .filter(\.isCardio)
            .map(\.target_seconds)
            .reduce(0, +) * max(set_count, 1)
    }
}

struct Exercise: Codable, Identifiable {
    var id = UUID()
    let name: String
    let category: String // "home_workout" or "cardio"
    let execution_style: String // "counted", "timed", "manual_timed"
    let target_reps: Int
    let target_seconds: Int
    let rest_seconds: Int
    
    enum CodingKeys: String, CodingKey {
        case name, category, execution_style, target_reps, target_seconds, rest_seconds
    }

    var isCardio: Bool {
        category.lowercased() == "cardio"
    }

    var isCardioWorkoutExercise: Bool {
        isCardio && execution_style == "manual_timed"
    }

    var targetDescription: String {
        if execution_style == "counted" {
            return "\(target_reps) reps"
        }

        if let duration = Self.formattedDurationDescription(target_seconds) {
            return duration
        }

        return "0 secs"
    }

    static func formattedDurationDescription(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }

        if seconds >= 60 && seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 min" : "\(minutes) mins"
        }

        return seconds == 1 ? "1 sec" : "\(seconds) secs"
    }
}

enum FitnessGoal: String, CaseIterable, Codable, Identifiable {
    case loseWeight = "Lose Weight"
    case gainMuscle = "Gain Muscle"
    case bodyRecomposition = "Lose Weight + Gain Muscle"

    var id: String { rawValue }
}

struct UserFitnessProfile: Codable {
    var weightKg: Double
    var heightCm: Double
    var goal: FitnessGoal

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case goal
    }

    var promptSummary: String {
        "Weight: \(Int(weightKg)) kg. Height: \(Int(heightCm)) cm. Goal: \(goal.rawValue)."
    }
}

struct WorkoutProgress: Codable {
    let planId: String
    let currentExerciseIndex: Int
    let isWorkoutComplete: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case currentExerciseIndex = "current_exercise_index"
        case isWorkoutComplete = "is_workout_complete"
        case updatedAt = "updated_at"
    }
}

struct WorkoutProgressRequest: Encodable {
    let planId: String
    let currentExerciseIndex: Int
    let isWorkoutComplete: Bool

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case currentExerciseIndex = "current_exercise_index"
        case isWorkoutComplete = "is_workout_complete"
    }
}

struct CompleteWorkoutRequest: Encodable {
    let planId: String?
    let dayName: String?
    let durationSeconds: Int?
    let setCount: Int?
    let exercises: [Exercise]

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case dayName = "day_name"
        case durationSeconds = "duration_seconds"
        case setCount = "set_count"
        case exercises
    }
}

struct CompleteWorkoutResponse: Codable {
    let completedOn: String
    let currentStreak: Int
    let alreadyCompleted: Bool
    let durationSeconds: Int?
    let caloriesBurned: Int?

    enum CodingKeys: String, CodingKey {
        case completedOn = "completed_on"
        case currentStreak = "current_streak"
        case alreadyCompleted = "already_completed"
        case durationSeconds = "duration_seconds"
        case caloriesBurned = "calories_burned"
    }
}

struct WorkoutSession: Codable, Identifiable {
    let id: String
    let completedOn: String
    let dayName: String?
    let durationSeconds: Int?
    let caloriesBurned: Int?
    let calorieEstimateSource: String?
    let setCount: Int?
    let exercises: [Exercise]
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case completedOn = "completed_on"
        case dayName = "day_name"
        case durationSeconds = "duration_seconds"
        case caloriesBurned = "calories_burned"
        case calorieEstimateSource = "calorie_estimate_source"
        case setCount = "set_count"
        case exercises
        case completedAt = "completed_at"
    }

    var isCardioWorkout: Bool {
        !exercises.isEmpty && exercises.allSatisfy(\.isCardioWorkoutExercise)
    }

    var cardioTargetDescription: String? {
        Exercise.formattedDurationDescription(cardioTargetSeconds)
    }

    private var cardioTargetSeconds: Int {
        exercises
            .filter(\.isCardio)
            .map(\.target_seconds)
            .reduce(0, +) * max(setCount ?? 1, 1)
    }
}

struct WorkoutCaloriesSummary: Codable {
    let sessions: [WorkoutSession]
    let averageCaloriesBurned: Double
    let totalCaloriesBurned: Int
    let workoutCount: Int

    enum CodingKeys: String, CodingKey {
        case sessions
        case averageCaloriesBurned = "average_calories_burned"
        case totalCaloriesBurned = "total_calories_burned"
        case workoutCount = "workout_count"
    }
}
