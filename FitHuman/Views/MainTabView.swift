import SwiftUI
import Combine
struct MainTabView: View {
    @ObservedObject var session: AuthSessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workoutViewModel: WorkoutViewModel
    @StateObject private var waterViewModel: WaterViewModel
    @State private var selectedTab: AppTab = .workout
    @State private var lastWorkoutReminderRefreshDay = MainTabView.localDayKey()

    init(session: AuthSessionViewModel) {
        self.session = session
        _workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(apiClient: session.apiClient))
        _waterViewModel = StateObject(wrappedValue: WaterViewModel(apiClient: session.apiClient))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WorkoutPlanView(viewModel: workoutViewModel)
                .tabItem {
                    Label("Workout", systemImage: "figure.run")
                }
                .tag(AppTab.workout)
            
            WaterTrackerView(viewModel: waterViewModel)
                .tabItem {
                    Label("Water", systemImage: "drop.fill")
                }
                .tag(AppTab.water)

            CaloriesBurnedView(viewModel: workoutViewModel)
                .tabItem {
                    Label("Calories Burned", systemImage: "flame.fill")
                }
                .tag(AppTab.calories)

            ProfileView(viewModel: workoutViewModel, session: session) {
                selectedTab = .workout
            }
            .environmentObject(waterViewModel)
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(AppTab.profile)
        }
        .tint(.blue) // Sets the active tab color globally
        .onChange(of: selectedTab) { _, tab in
            guard tab != .profile,
                  workoutViewModel.hasSavedPlan,
                  workoutViewModel.isSettingUpPlan else { return }

            workoutViewModel.cancelPlanSetup()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await refreshDailyReminderInputs(refreshWorkoutForNewDay: true)
            }
        }
        .onChange(of: workoutViewModel.dailyWorkoutReminderState) { _, newState in
            waterViewModel.updateWorkoutReminderState(newState)
        }
        .task {
            await refreshDailyReminderInputs(refreshWorkoutForNewDay: false)
        }
    }

    @MainActor
    private func refreshDailyReminderInputs(refreshWorkoutForNewDay: Bool) async {
        let currentDay = Self.localDayKey()

        if refreshWorkoutForNewDay && currentDay != lastWorkoutReminderRefreshDay {
            await workoutViewModel.loadInitialData(force: true)
            lastWorkoutReminderRefreshDay = currentDay
        } else {
            await workoutViewModel.loadInitialData()
        }

        waterViewModel.updateWorkoutReminderState(workoutViewModel.dailyWorkoutReminderState)
        await waterViewModel.loadToday()
    }

    private static func localDayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum AppTab: Hashable {
    case workout
    case water
    case calories
    case profile
}
