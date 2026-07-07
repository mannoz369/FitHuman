import Foundation
import SwiftUI
import Combine

@MainActor
class WorkoutViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var dailyPlan: DailyPlan?
    @Published var fullWeeklyPlan: [DailyPlan] = []
    @Published var userProfile: UserFitnessProfile?
    @Published var isGeneratingPlan = false
    @Published var isLoadingPlan = true
    @Published private(set) var hasLoadedInitialData = false
    @Published var generationErrorMessage: String?
    @Published var syncErrorMessage: String?
    @Published var isSettingUpPlan = false

    // MARK: - Active Workout State
    @Published var currentExerciseIndex = 0
    @Published var isWorkoutComplete = false
    @Published var isResting = false
    @Published var currentStreak = 0
    @Published var sessionDurationSeconds = 0
    @Published var completedCaloriesBurned: Int?
    @Published var isEstimatingCalories = false
    @Published var isCompletingWorkout = false
    @Published var caloriesSummary: WorkoutCaloriesSummary?
    @Published var isLoadingCaloriesSummary = false
    @Published var caloriesSummaryErrorMessage: String?
    @Published var completedWorkoutStreakAnimation: StreakAnimation?

    private let apiClient: BackendAPIClient
    private var currentPlanId: String?
    private var planStartDate: Date?
    private var planEndDateValue: Date?
    private var daysRemaining = 30
    private var backendSaysNeedsNewPlan = false

    struct StreakAnimation: Identifiable, Equatable {
        let id = UUID()
        let startCount: Int
        let endCount: Int
    }

    init(apiClient: BackendAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Computed Properties
    var currentExercise: Exercise? {
        guard let exercises = dailyPlan?.exercises,
              !exercises.isEmpty,
              currentExerciseIndex < totalWorkoutSteps else {
            return nil
        }
        return exercises[currentExerciseIndex % exercises.count]
    }

    var currentSetNumber: Int {
        guard let exercises = dailyPlan?.exercises, !exercises.isEmpty else {
            return 0
        }
        return (currentExerciseIndex / exercises.count) + 1
    }

    var totalSetCount: Int {
        dailyPlan?.set_count ?? 0
    }

    var currentExercisePosition: Int {
        guard let exercises = dailyPlan?.exercises, !exercises.isEmpty else {
            return 0
        }
        return (currentExerciseIndex % exercises.count) + 1
    }

    var totalWorkoutSteps: Int {
        guard let plan = dailyPlan, !plan.is_rest_day else {
            return 0
        }
        return plan.exercises.count * max(plan.set_count, 1)
    }

    var hasSavedPlan: Bool {
        currentPlanId != nil && !fullWeeklyPlan.isEmpty
    }

    var needsPlanSetup: Bool {
        userProfile == nil || !hasSavedPlan || isSettingUpPlan
    }

    var planEndDate: Date? {
        planEndDateValue
    }

    var isPlanExpired: Bool {
        hasSavedPlan && (backendSaysNeedsNewPlan || daysRemaining <= 0)
    }

    var planDaysRemaining: Int {
        daysRemaining
    }

    var isInitialLoadPending: Bool {
        !hasLoadedInitialData
    }

    var dailyWorkoutReminderState: DailyWorkoutReminderState? {
        guard hasSavedPlan, !isPlanExpired, let dailyPlan else {
            return nil
        }

        return DailyWorkoutReminderState(
            isRestDay: dailyPlan.is_rest_day,
            isWorkoutComplete: isWorkoutComplete
        )
    }

    // MARK: - Data Loading
    func loadInitialData(force: Bool = false) async {
        guard force || !hasLoadedInitialData else { return }

        isLoadingPlan = true
        syncErrorMessage = nil
        defer {
            hasLoadedInitialData = true
            isLoadingPlan = false
        }

        do {
            let user = try await apiClient.getCurrentUser()
            userProfile = user.profile
            currentStreak = user.currentStreak

            let response = try await apiClient.getCurrentWorkoutPlan()
            applyCurrentPlanResponse(response)

            let todayIsComplete = response.todayIsWorkoutComplete == true || response.todayProgress?.isWorkoutComplete == true
            if todayIsComplete {
                await hydrateTodaysCompletedSession()
            } else if hasSavedPlan && response.todayProgress == nil {
                await loadWorkoutProgress()
            }

        } catch {
            setSyncError(error)
        }
    }

    // MARK: - Active Workout Actions
    func startWorkout() {
        currentExerciseIndex = 0
        isWorkoutComplete = false
        sessionDurationSeconds = 0
        completedCaloriesBurned = nil
        isEstimatingCalories = false
        completedWorkoutStreakAnimation = nil
        Task {
            await saveWorkoutProgress()
        }
    }

    func recordWorkoutSecond() {
        guard !isWorkoutComplete, !isResting, currentExercise != nil else { return }
        sessionDurationSeconds += 1
    }

    func completeCurrentExercise() {
        guard totalWorkoutSteps > 0, !isCompletingWorkout else { return }

        if currentExerciseIndex < totalWorkoutSteps - 1 {
            isResting = true
            Task {
                await saveWorkoutProgress(currentExerciseIndex: currentExerciseIndex + 1)
            }
        } else {
            isWorkoutComplete = true
            Task {
                await completeWorkoutOnBackend()
            }
        }
    }

    func nextExercise() {
        isResting = false

        guard totalWorkoutSteps > 0, !isCompletingWorkout else { return }

        if currentExerciseIndex < totalWorkoutSteps - 1 {
            currentExerciseIndex += 1
            Task {
                await saveWorkoutProgress()
            }
        } else {
            isWorkoutComplete = true
            Task {
                await completeWorkoutOnBackend()
            }
        }
    }

    func loadCaloriesSummary() async {
        isLoadingCaloriesSummary = true
        caloriesSummaryErrorMessage = nil

        do {
            caloriesSummary = try await apiClient.getWorkoutCaloriesSummary()
        } catch {
            guard !Self.isCancellation(error) else { return }
            caloriesSummaryErrorMessage = error.localizedDescription
        }

        isLoadingCaloriesSummary = false
    }

    func clearCompletedWorkoutStreakAnimation() {
        completedWorkoutStreakAnimation = nil
    }

    // MARK: - Plan Management
    func beginPlanSetup(clearProfile: Bool = false) {
        generationErrorMessage = nil
        isSettingUpPlan = true

        if clearProfile {
            userProfile = nil
        }
    }

    func cancelPlanSetup() {
        generationErrorMessage = nil
        isSettingUpPlan = false
    }

    func continueCurrentPlanForAnotherMonth() {
        isGeneratingPlan = true
        generationErrorMessage = nil

        Task {
            do {
                let plan = try await apiClient.continueCurrentWorkoutPlan()
                applyPlan(plan)
                currentExerciseIndex = 0
                isWorkoutComplete = false
                isResting = false
                sessionDurationSeconds = 0
                completedCaloriesBurned = nil
                isEstimatingCalories = false
                completedWorkoutStreakAnimation = nil
                backendSaysNeedsNewPlan = false
                await saveWorkoutProgress()
            } catch {
                setGenerationError(error)
            }

            isGeneratingPlan = false
        }
    }

    func generatePlan(profile: UserFitnessProfile) async {
        isGeneratingPlan = true
        generationErrorMessage = nil
        syncErrorMessage = nil
        userProfile = profile

        do {
            let plan = try await apiClient.generateWorkoutPlan(profile: profile)
            applyPlan(plan)
            isSettingUpPlan = false
            backendSaysNeedsNewPlan = false
        } catch {
            setGenerationError(error)
        }

        isGeneratingPlan = false
    }

    // MARK: - Backend Sync
    private func loadWorkoutProgress() async {
        guard let currentPlanId else { return }

        do {
            guard let progress = try await apiClient.getWorkoutProgress(planId: currentPlanId) else {
                return
            }

            applyWorkoutProgress(progress)
        } catch {
            setSyncError(error)
        }
    }

    private func saveWorkoutProgress(
        currentExerciseIndex savedExerciseIndex: Int? = nil,
        isWorkoutComplete savedWorkoutComplete: Bool? = nil
    ) async {
        guard let currentPlanId else { return }

        do {
            _ = try await apiClient.saveWorkoutProgress(
                planId: currentPlanId,
                currentExerciseIndex: savedExerciseIndex ?? currentExerciseIndex,
                isWorkoutComplete: savedWorkoutComplete ?? isWorkoutComplete
            )
        } catch {
            setSyncError(error)
        }
    }

    private func completeWorkoutOnBackend() async {
        guard !isCompletingWorkout else { return }

        let streakBeforeCompletion = currentStreak
        isCompletingWorkout = true
        syncErrorMessage = nil
        do {
            let response = try await apiClient.completeWorkout(
                planId: currentPlanId,
                dayName: dailyPlan?.day_name,
                durationSeconds: sessionDurationSeconds,
                setCount: dailyPlan?.set_count,
                exercises: dailyPlan?.exercises ?? []
            )
            currentStreak = response.currentStreak
            completedWorkoutStreakAnimation = StreakAnimation(
                startCount: streakBeforeCompletion,
                endCount: response.currentStreak
            )
            if let durationSeconds = response.durationSeconds {
                sessionDurationSeconds = durationSeconds
            }
            completedCaloriesBurned = response.caloriesBurned
            isEstimatingCalories = response.caloriesBurned == nil
            isWorkoutComplete = true
            Task {
                await refreshCompletedCalories(completedOn: response.completedOn)
            }
        } catch {
            isWorkoutComplete = false
            completedCaloriesBurned = nil
            isEstimatingCalories = false
            setSyncError(error)
        }
        isCompletingWorkout = false
    }

    private func refreshCompletedCalories(completedOn: String) async {
        for attempt in 0..<10 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            await loadCaloriesSummary()
            guard let session = caloriesSummary?.sessions.first(where: { $0.completedOn == completedOn }) else {
                continue
            }

            if let calories = session.caloriesBurned {
                completedCaloriesBurned = calories
                isEstimatingCalories = false
                return
            }
        }

        isEstimatingCalories = false
    }

    private func hydrateTodaysCompletedSession() async {
        let completedOn = completedOnKey()
        await loadCaloriesSummary()

        guard let session = caloriesSummary?.sessions.first(where: { $0.completedOn == completedOn }) else {
            return
        }

        if let durationSeconds = session.durationSeconds {
            self.sessionDurationSeconds = durationSeconds
        }
        completedCaloriesBurned = session.caloriesBurned
        isEstimatingCalories = session.caloriesBurned == nil

        if session.caloriesBurned == nil {
            Task {
                await refreshCompletedCalories(completedOn: completedOn)
            }
        }
    }

    private func applyCurrentPlanResponse(_ response: CurrentWorkoutPlanResponse) {
        backendSaysNeedsNewPlan = response.needs_new_plan
        if let currentStreak = response.currentStreak {
            self.currentStreak = currentStreak
        }

        guard let plan = response.plan else {
            currentPlanId = nil
            dailyPlan = nil
            fullWeeklyPlan = []
            planStartDate = nil
            planEndDateValue = nil
            daysRemaining = 30
            currentExerciseIndex = 0
            isWorkoutComplete = false
            isResting = false
            sessionDurationSeconds = 0
            completedCaloriesBurned = nil
            isEstimatingCalories = false
            completedWorkoutStreakAnimation = nil
            return
        }

        applyPlan(plan)

        if let todayProgress = response.todayProgress {
            applyWorkoutProgress(todayProgress)
        } else if response.todayIsWorkoutComplete == true {
            currentExerciseIndex = 0
            isWorkoutComplete = true
            isResting = false
        }
    }

    private func applyPlan(_ plan: WorkoutPlan) {
        currentPlanId = plan.id
        fullWeeklyPlan = plan.weekly_plan
        dailyPlan = plan.today_plan ?? computedTodayPlan(from: plan)
        userProfile = plan.profile_snapshot
        planStartDate = plan.starts_at
        planEndDateValue = plan.ends_at
        daysRemaining = plan.days_remaining
        currentExerciseIndex = 0
        isWorkoutComplete = false
        isResting = false
        sessionDurationSeconds = 0
        completedCaloriesBurned = nil
        isEstimatingCalories = false
        completedWorkoutStreakAnimation = nil
    }

    private func applyWorkoutProgress(_ progress: WorkoutProgress) {
        currentExerciseIndex = progress.currentExerciseIndex
        isWorkoutComplete = progress.isWorkoutComplete
        isResting = false
    }

    private func setSyncError(_ error: Error) {
        guard !Self.isCancellation(error) else { return }
        syncErrorMessage = error.localizedDescription
    }

    private func setGenerationError(_ error: Error) {
        guard !Self.isCancellation(error) else { return }
        generationErrorMessage = error.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func completedOnKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func computedTodayPlan(from plan: WorkoutPlan) -> DailyPlan? {
        guard !plan.weekly_plan.isEmpty else { return nil }

        let startOfPlan = Calendar.current.startOfDay(for: plan.starts_at)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let elapsedDays = Calendar.current.dateComponents([.day], from: startOfPlan, to: startOfToday).day ?? 0
        let planIndex = max(elapsedDays, 0) % plan.weekly_plan.count
        return plan.weekly_plan[planIndex]
    }
}
