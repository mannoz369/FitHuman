import SwiftUI
import Combine

struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var timeRemaining: Int = 0
    @State private var timerActive = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // This allows us to close the sheet and go back to the main screen
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 30) {
            
            // --- NEW: WORKOUT COMPLETE STATE ---
            if viewModel.isWorkoutComplete {
                VStack(spacing: 20) {
                    
                    Text("Workout Complete!")
                        .font(.largeTitle).bold()
                    
                    completionStreakView

                    Text("Duration: \(formattedDuration(viewModel.sessionDurationSeconds))")
                        .font(.title3.bold())

                    if let calories = viewModel.completedCaloriesBurned {
                        Text("Estimated Calories: \(calories)")
                            .font(.title3.bold())
                    } else if viewModel.isEstimatingCalories {
                        ProgressView("Estimating calories...")
                    }
                    
                    Button("Finish") {
                        viewModel.clearCompletedWorkoutStreakAnimation()
                        dismiss() // Closes the active workout screen
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            // --- EXISTING EXERCISE STATE ---
            else if let exercise = viewModel.currentExercise {
                Text("Set \(viewModel.currentSetNumber) of \(viewModel.totalSetCount)")
                    .font(.title3.bold())
                    .foregroundColor(.secondary)

                Text(exercise.name)
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // STATE 1: Counted (Reps)
                if exercise.execution_style == "counted" {
                    Text(exercise.targetDescription)
                        .font(.system(size: 60, weight: .bold))
                    Button("Mark as Done") {
                        viewModel.completeCurrentExercise()
                    }
                    .disabled(viewModel.isCompletingWorkout)
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                // STATE 2: Manual Timed (Running/Walking)
                else if exercise.execution_style == "manual_timed" {
                    Text("Target: \(exercise.targetDescription)")
                        .font(.system(size: 40, weight: .bold))
                    Text("Go outside or use a treadmill!")
                        .foregroundColor(.secondary)
                    Button("Mark as Done") {
                        viewModel.completeCurrentExercise()
                    }
                    .disabled(viewModel.isCompletingWorkout)
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                // STATE 3: Timed (Active in-app timer)
                else if exercise.execution_style == "timed" {
                    Text("\(timeRemaining)s")
                        .font(.system(size: 80, weight: .bold, design: .monospaced))
                    
                    Button(timerActive ? "Pause" : "Start") {
                        timerActive.toggle()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .onAppear { timeRemaining = exercise.target_seconds }
                }
            }
        }
        .onReceive(timer) { _ in
            guard let exercise = viewModel.currentExercise else { return }

            if shouldCountWorkoutSecond(for: exercise) {
                viewModel.recordWorkoutSecond()
            }

            if exercise.execution_style == "timed" {
                if timerActive && timeRemaining > 0 { timeRemaining -= 1 }
                if timeRemaining == 0 && timerActive {
                    timerActive = false
                    viewModel.completeCurrentExercise()
                }
            }
        }
        .onChange(of: viewModel.currentExerciseIndex) { _, _ in
            timeRemaining = viewModel.currentExercise?.target_seconds ?? 0
            timerActive = false
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $viewModel.isResting) {
            RestTimerView(viewModel: viewModel)
        }
        #else
        .sheet(isPresented: $viewModel.isResting) {
            RestTimerView(viewModel: viewModel)
        }
        #endif
    }

    @ViewBuilder
    private var completionStreakView: some View {
        if let streakAnimation = viewModel.completedWorkoutStreakAnimation {
            StreakCelebrationView(
                startCount: streakAnimation.startCount,
                endCount: streakAnimation.endCount
            )
        } else {
            StreakLabel(currentStreak: viewModel.currentStreak)
                .font(.title2)
                .foregroundColor(.orange)
        }
    }

    private func shouldCountWorkoutSecond(for exercise: Exercise) -> Bool {
        guard !viewModel.isWorkoutComplete, !viewModel.isResting else { return false }
        if exercise.execution_style == "timed" {
            return timerActive
        }
        return true
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }
}

// Reusable Button Style
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.bold())
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(15)
            .padding(.horizontal)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
