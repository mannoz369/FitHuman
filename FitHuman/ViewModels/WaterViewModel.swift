import SwiftUI
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
class WaterViewModel: ObservableObject {
    @Published var currentIntakeML: Double = 0
    @Published var dailyGoalML: Double = 2500
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var historyDays: [WaterHistoryDay] = []
    @Published private(set) var averageIntakeML: Double = 0
    @Published private(set) var currentDay: String?
    @Published private(set) var lastIntakeAt: Date?

    private let apiClient: BackendAPIClient
    private let hydrationReminderScheduler = HydrationReminderScheduler()
    private let workoutReminderScheduler = DailyWorkoutReminderScheduler()
    private var scheduledReminderState: HydrationReminderState?
    private var scheduledWorkoutReminderState: WorkoutReminderScheduleState?
    private var lastAppliedLog: WaterLog?
    private var workoutReminderState: DailyWorkoutReminderState?

    init(apiClient: BackendAPIClient) {
        self.apiClient = apiClient
    }

    var progress: Double {
        min(currentIntakeML / dailyGoalML, 1.0)
    }

    var displayedDay: String {
        currentDay ?? "Today"
    }

    var averageIntakeText: String {
        "\(Int(averageIntakeML.rounded())) mL"
    }

    var deviceTimeZoneIdentifier: String {
        TimeZone.current.identifier
    }

    var deviceDay: String {
        Self.localDayKey()
    }

    func loadToday() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            apply(try await apiClient.getTodayWater())
            apply(try await apiClient.getWaterHistory(days: 7))
        } catch {
            guard !Self.isCancellation(error) else {
                errorMessage = nil
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func addGlass() {
        addWater(amountML: 250)
    }

    func addWater(amountML: Double) {
        Task {
            do {
                let log = try await apiClient.addWater(amountML: amountML)
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    apply(log)
                }
                apply(try await apiClient.getWaterHistory(days: 7))
            } catch {
                guard !Self.isCancellation(error) else {
                    errorMessage = nil
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func checkMidnightReset() {
        Task {
            await loadToday()
        }
    }

    func updateWorkoutReminderState(_ state: DailyWorkoutReminderState?) {
        guard workoutReminderState != state else {
            return
        }

        workoutReminderState = state

        syncWorkoutReminder(forDay: lastAppliedLog?.day ?? Self.localDayKey())
    }

    private func apply(_ log: WaterLog) {
        lastAppliedLog = log
        currentDay = log.day
        currentIntakeML = log.currentIntakeML
        dailyGoalML = log.dailyGoalML
        lastIntakeAt = log.lastIntakeAt
        syncHydrationReminders(for: log)
        syncWorkoutReminder(forDay: log.day)
    }

    private func apply(_ history: WaterHistory) {
        historyDays = history.days
        averageIntakeML = history.averageIntakeML
    }

    private static func localDayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func syncHydrationReminders(for log: WaterLog) {
        let wakeTime = HydrationReminderSettings.wakeTime()
        let reminderState = HydrationReminderState(
            day: log.day,
            currentIntakeML: log.currentIntakeML,
            dailyGoalML: log.dailyGoalML,
            lastIntakeAt: log.lastIntakeAt,
            wakeHour: wakeTime.hour,
            wakeMinute: wakeTime.minute
        )

        guard scheduledReminderState != reminderState else {
            return
        }

        scheduledReminderState = reminderState

        Task {
            await hydrationReminderScheduler.scheduleReminders(
                lastIntakeAt: log.lastIntakeAt,
                currentIntakeML: log.currentIntakeML,
                dailyGoalML: log.dailyGoalML,
                wakeHour: wakeTime.hour,
                wakeMinute: wakeTime.minute
            )
        }
    }

    private func syncWorkoutReminder(forDay day: String) {
        let wakeTime = HydrationReminderSettings.wakeTime()
        let reminderState = WorkoutReminderScheduleState(
            day: day,
            wakeHour: wakeTime.hour,
            wakeMinute: wakeTime.minute,
            workoutReminderState: workoutReminderState
        )

        guard scheduledWorkoutReminderState != reminderState else {
            return
        }

        scheduledWorkoutReminderState = reminderState

        Task {
            await workoutReminderScheduler.scheduleReminder(
                state: workoutReminderState,
                wakeHour: wakeTime.hour,
                wakeMinute: wakeTime.minute
            )
        }
    }
}

struct DailyWorkoutReminderState: Equatable {
    let isRestDay: Bool
    let isWorkoutComplete: Bool

    var shouldIncludeIncompleteWorkoutReminder: Bool {
        !isRestDay && !isWorkoutComplete
    }
}

private struct HydrationReminderState: Equatable {
    let day: String
    let currentIntakeML: Double
    let dailyGoalML: Double
    let lastIntakeAt: Date?
    let wakeHour: Int
    let wakeMinute: Int
}

private struct WorkoutReminderScheduleState: Equatable {
    let day: String
    let wakeHour: Int
    let wakeMinute: Int
    let workoutReminderState: DailyWorkoutReminderState?
}

enum HydrationReminderSettings {
    static let wakeHourKey = "hydrationReminderWakeHour"
    static let wakeMinuteKey = "hydrationReminderWakeMinute"

    private static let defaultWakeHour = 8
    private static let defaultWakeMinute = 0

    static func wakeTime() -> (hour: Int, minute: Int) {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: wakeHourKey) == nil
            ? defaultWakeHour
            : defaults.integer(forKey: wakeHourKey)
        let minute = defaults.object(forKey: wakeMinuteKey) == nil
            ? defaultWakeMinute
            : defaults.integer(forKey: wakeMinuteKey)

        return (
            hour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59)
        )
    }

    static func wakeTimeDate(referenceDate: Date = Date()) -> Date {
        let wakeTime = wakeTime()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)

        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: wakeTime.hour,
                minute: wakeTime.minute
            )
        ) ?? referenceDate
    }

    static func saveWakeTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        UserDefaults.standard.set(components.hour ?? defaultWakeHour, forKey: wakeHourKey)
        UserDefaults.standard.set(components.minute ?? defaultWakeMinute, forKey: wakeMinuteKey)
    }
}

private final class HydrationReminderScheduler {
    private let currentOneHourReminderIdentifier = "water-intake-reminder-current-1-hour"
    private let currentTwoHourReminderIdentifier = "water-intake-reminder-current-2-hours"
    private let legacyRollingReminderCleanupDays = 31

    private var currentReminderIdentifiers: [String] {
        [currentOneHourReminderIdentifier, currentTwoHourReminderIdentifier]
    }

    func scheduleReminders(
        lastIntakeAt: Date?,
        currentIntakeML: Double,
        dailyGoalML: Double,
        wakeHour: Int,
        wakeMinute: Int
    ) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let now = Date()
        center.removePendingNotificationRequests(withIdentifiers: reminderIdentifiers(from: now))
        center.removeDeliveredNotifications(withIdentifiers: reminderIdentifiers(from: now))

        guard await notificationsAllowed(center: center) else {
            return
        }

        guard currentIntakeML < dailyGoalML else {
            return
        }

        guard let lastIntakeAt else {
            let wakeDate = wakeDate(hour: wakeHour, minute: wakeMinute, referenceDate: now)
            let twoHourDate = wakeDate.addingTimeInterval(2 * 60 * 60)

            if twoHourDate <= now {
                await scheduleReminder(
                    center: center,
                    identifier: currentTwoHourReminderIdentifier,
                    title: "Drink water",
                    body: "Still no water logged today.",
                    targetDate: now.addingTimeInterval(1)
                )
                return
            }

            if wakeDate <= now {
                await scheduleReminder(
                    center: center,
                    identifier: currentOneHourReminderIdentifier,
                    title: "Drink water",
                    body: "You have not logged water yet today.",
                    targetDate: now.addingTimeInterval(1)
                )
            } else {
                await scheduleReminder(
                    center: center,
                    identifier: currentOneHourReminderIdentifier,
                    title: "Drink water",
                    body: "You have not logged water yet today.",
                    targetDate: wakeDate
                )
            }

            await scheduleReminder(
                center: center,
                identifier: currentTwoHourReminderIdentifier,
                title: "Drink water",
                body: "Still no water logged today.",
                targetDate: twoHourDate
            )
            return
        }

        let oneHourDate = lastIntakeAt.addingTimeInterval(60 * 60)
        let twoHourDate = lastIntakeAt.addingTimeInterval(2 * 60 * 60)

        if twoHourDate <= now {
            await scheduleReminder(
                center: center,
                identifier: currentTwoHourReminderIdentifier,
                title: "Drink water",
                body: "It has been 2 hours since you drank water.",
                targetDate: now.addingTimeInterval(1)
            )
            return
        }

        await scheduleReminder(
            center: center,
            identifier: currentOneHourReminderIdentifier,
            title: "Drink water",
            body: "It has been 1 hour since you drank water.",
            targetDate: max(oneHourDate, now.addingTimeInterval(1))
        )
        await scheduleReminder(
            center: center,
            identifier: currentTwoHourReminderIdentifier,
            title: "Drink water",
            body: "It has been 2 hours since you drank water.",
            targetDate: twoHourDate
        )
        #endif
    }

    #if canImport(UserNotifications)
    private func notificationsAllowed(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func scheduleReminder(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        targetDate: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let interval = max(targetDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try? await center.add(request)
    }

    private func wakeDate(hour: Int, minute: Int, referenceDate: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)

        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute
            )
        ) ?? referenceDate
    }

    private func reminderIdentifiers(from referenceDate: Date) -> [String] {
        let calendar = Calendar.current
        var identifiers = currentReminderIdentifiers

        for offset in 0..<legacyRollingReminderCleanupDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: referenceDate) else {
                continue
            }

            identifiers.append(rollingReminderIdentifier(day: day, reminderNumber: 1))
            identifiers.append(rollingReminderIdentifier(day: day, reminderNumber: 2))
        }

        return identifiers
    }

    private func rollingReminderIdentifier(day: Date, reminderNumber: Int) -> String {
        "water-intake-reminder-\(Self.dayIdentifierFormatter.string(from: day))-\(reminderNumber)"
    }

    private static let dayIdentifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    #endif
}

private final class DailyWorkoutReminderScheduler {
    private let currentWorkoutReminderIdentifier = "daily-workout-reminder-current"

    func scheduleReminder(
        state: DailyWorkoutReminderState?,
        wakeHour: Int,
        wakeMinute: Int
    ) async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [currentWorkoutReminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [currentWorkoutReminderIdentifier])

        guard state?.shouldIncludeIncompleteWorkoutReminder == true else {
            return
        }

        guard await notificationsAllowed(center: center) else {
            return
        }

        let now = Date()
        let wakeDate = wakeDate(hour: wakeHour, minute: wakeMinute, referenceDate: now)
        await scheduleReminder(
            center: center,
            targetDate: wakeDate <= now ? now.addingTimeInterval(1) : wakeDate
        )
        #endif
    }

    #if canImport(UserNotifications)
    private func notificationsAllowed(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func scheduleReminder(
        center: UNUserNotificationCenter,
        targetDate: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Workout reminder"
        content.body = "You have not completed today's workout yet."
        content.sound = .default

        let interval = max(targetDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: currentWorkoutReminderIdentifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    private func wakeDate(hour: Int, minute: Int, referenceDate: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)

        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute
            )
        ) ?? referenceDate
    }
    #endif
}
