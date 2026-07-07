import SwiftUI

struct CaloriesBurnedView: View {
    @ObservedObject var viewModel: WorkoutViewModel

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoadingCaloriesSummary && viewModel.caloriesSummary == nil {
                    ProgressView("Loading calories...")
                } else if let summary = viewModel.caloriesSummary {
                    caloriesContent(summary)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Calories Burned")
            .task {
                await viewModel.loadCaloriesSummary()
            }
            .refreshable {
                await viewModel.loadCaloriesSummary()
            }
        }
    }

    private func caloriesContent(_ summary: WorkoutCaloriesSummary) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(summary.averageCaloriesBurned.rounded()))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("avg cal")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        metricLabel(title: "Total", value: "\(summary.totalCaloriesBurned)")
                        Spacer()
                        metricLabel(title: "Workouts", value: "\(summary.workoutCount)")
                    }
                }
                .padding(.vertical, 6)
            }

            if let errorMessage = viewModel.caloriesSummaryErrorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("History") {
                if summary.sessions.isEmpty {
                    Text("Completed workouts will appear here.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(summary.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            Text("No calorie history yet")
                .font(.title2.bold())
            Text("Finish a workout to save duration and estimated calories.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func metricLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.dayName ?? "Workout")
                        .font(.headline)
                    Text(session.completedOn)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(session.caloriesBurned.map { "\($0) cal" } ?? "Pending")
                    .font(.headline)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 0) {
                historyMetric(
                    systemImage: "timer",
                    value: sessionEffortDescription(session)
                )
                .frame(width: 100, alignment: .leading)

                historyMetric(
                    systemImage: "figure.strengthtraining.traditional",
                    value: exerciseCountDescription(session.exercises.count)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func historyMetric(systemImage: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, alignment: .center)

            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func sessionEffortDescription(_ session: WorkoutSession) -> String {
        if session.isCardioWorkout {
            return session.cardioTargetDescription ?? "Cardio target"
        }

        return formattedDuration(session.durationSeconds ?? 0)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    private func exerciseCountDescription(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }
}
