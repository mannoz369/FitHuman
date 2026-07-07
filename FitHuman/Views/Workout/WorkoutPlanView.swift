import SwiftUI

struct WorkoutPlanView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var isWorkoutActive = false

    var body: some View {
        NavigationView {
            content
                .navigationTitle(navigationTitle)
                .task {
                    await viewModel.loadInitialData()
                }
                .sheet(isPresented: $isWorkoutActive) {
                    ActiveWorkoutView(viewModel: viewModel)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isInitialLoadPending || viewModel.isLoadingPlan {
            loadingView(message: "Loading your plan...")
        } else if viewModel.isGeneratingPlan {
            loadingView
        } else if viewModel.needsPlanSetup {
            PlanSetupView(
                viewModel: viewModel,
                title: viewModel.hasSavedPlan ? "Update Your Plan" : "Build Your Plan",
                subtitle: "Enter your current stats so Gemini can generate your monthly workout plan.",
                buttonTitle: viewModel.hasSavedPlan ? "Generate New Plan" : "Generate Workout Plan",
                prefillsExistingProfile: !viewModel.hasSavedPlan
            )
        } else if viewModel.isPlanExpired {
            monthlyPlanCompleteView
        } else if let plan = viewModel.dailyPlan {
            todaysPlanView(plan)
        } else {
            PlanSetupView(
                viewModel: viewModel,
                title: "Build Your Plan",
                subtitle: "Enter your current stats so Gemini can generate your monthly workout plan.",
                buttonTitle: "Generate Workout Plan"
            )
        }
    }

    private var navigationTitle: String {
        guard !viewModel.isInitialLoadPending,
              !viewModel.isLoadingPlan,
              !viewModel.isGeneratingPlan,
              !viewModel.needsPlanSetup,
              !viewModel.isPlanExpired,
              viewModel.dailyPlan != nil else {
            return ""
        }

        return "Today's Plan"
    }

    private var loadingView: some View {
        loadingView(message: "Generating plan...")
    }

    private func loadingView(message: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .foregroundColor(.secondary)
        }
    }

    private var monthlyPlanCompleteView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 84))
                .foregroundColor(.blue)

            Text("Monthly Plan Complete")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("You can continue this plan for another month or generate a fresh plan with your latest stats.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Continue This Plan") {
                viewModel.continueCurrentPlanForAnotherMonth()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Generate New Plan") {
                viewModel.beginPlanSetup()
            }
            .foregroundColor(.blue)
        }
        .padding()
    }

    @ViewBuilder
    private func todaysPlanView(_ plan: DailyPlan) -> some View {
        VStack {
            if let syncError = viewModel.syncErrorMessage {
                Text(syncError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top)
            }

            if !viewModel.isWorkoutComplete {
                topRightStreakBadge
            }

            if plan.is_rest_day {
                Text("Today is a Rest Day!")
                    .font(.title)
                    .foregroundColor(.secondary)
            } else if viewModel.isWorkoutComplete {
                workoutCompleteView(plan)
            } else {
                activePlanList(plan)
            }
        }
    }

    private var topRightStreakBadge: some View {
        HStack {
            Spacer()

            StreakLabel(currentStreak: viewModel.currentStreak)
                .font(.subheadline.bold())
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.16))
                .clipShape(Capsule())
                .offset(y: -59)
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private func workoutCompleteView(_ plan: DailyPlan) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)

            Text("You crushed it today!")
                .font(.largeTitle).bold()

            StreakLabel(currentStreak: viewModel.currentStreak)
                .font(.title2)
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(10)

            if !plan.isCardioWorkout && viewModel.sessionDurationSeconds > 0 {
                Text("Duration: \(formattedDuration(viewModel.sessionDurationSeconds))")
                    .font(.headline)
            }

            if let calories = viewModel.completedCaloriesBurned {
                Text("Estimated Calories: \(calories)")
                    .font(.headline)
            } else if viewModel.isEstimatingCalories {
                ProgressView("Estimating calories...")
            }

            Text("Come back tomorrow for your next routine.")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func activePlanList(_ plan: DailyPlan) -> some View {
        VStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set \(max(viewModel.currentSetNumber, 1)) of \(max(viewModel.totalSetCount, 1))")
                    .font(.title3.bold())
                Text("\(plan.exercises.count) exercises repeated as a circuit")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(viewModel.planDaysRemaining) days left in this monthly plan")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top,-50)

            List(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                HStack {
                    if viewModel.currentSetNumber > 0 && index < viewModel.currentExercisePosition - 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    } else if viewModel.currentSetNumber > 0 && index == viewModel.currentExercisePosition - 1 {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray.opacity(0.3))
                            .font(.title2)
                    }

                    Text(exercise.name)
                        .font(.headline)
                        .padding(.leading, 5)

                    Spacer()

                    Text(exercise.targetDescription)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

            }
            .padding(.top,3)
            Button(viewModel.currentExerciseIndex > 0 || viewModel.sessionDurationSeconds > 0 ? "Resume Workout" : "Start Today's Workout") {
                if viewModel.currentExerciseIndex == 0 && viewModel.sessionDurationSeconds == 0 {
                    viewModel.startWorkout()
                }
                isWorkoutActive = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding()
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }
}
