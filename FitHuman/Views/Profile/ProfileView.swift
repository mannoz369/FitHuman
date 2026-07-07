import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @ObservedObject var session: AuthSessionViewModel
    @EnvironmentObject private var waterViewModel: WaterViewModel
    var onShowWorkout: (() -> Void)?

    @State private var isChangingPlan = false
    @State private var hydrationWakeTime = HydrationReminderSettings.wakeTimeDate()

    var body: some View {
        NavigationView {
            content
                .navigationTitle(navigationTitle)
        }
        .onDisappear {
            stopPlanChange()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isGeneratingPlan {
            generatingView
        } else if isChangingPlan {
            PlanSetupView(
                viewModel: viewModel,
                title: viewModel.hasSavedPlan ? "Update Your Plan" : "Build Your Plan",
                subtitle: "Confirm your current stats and goal before Gemini builds your monthly workout plan.",
                buttonTitle: viewModel.hasSavedPlan ? "Generate New Plan" : "Generate Workout Plan",
                prefillsExistingProfile: true,
                onPlanGenerated: {
                    isChangingPlan = false
                    onShowWorkout?()
                },
                onCancel: stopPlanChange
            )
        } else {
            profileSummary
        }
    }

    private var navigationTitle: String {
        isChangingPlan || viewModel.isGeneratingPlan ? "" : "Profile"
    }

    private var generatingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating plan...")
                .foregroundColor(.secondary)
        }
    }

    private var profileSummary: some View {
        Form {
            if let user = session.currentUser {
                Section("Account") {
                    LabeledContent("Name", value: displayName(for: user))
                    LabeledContent("Email", value: user.email)
                }
            }

            if let profile = viewModel.userProfile {
                Section("Body") {
                    LabeledContent("Weight", value: "\(Int(profile.weightKg)) kg")
                    LabeledContent("Height", value: "\(Int(profile.heightCm)) cm")
                    LabeledContent("Goal", value: profile.goal.rawValue)
                }
            }

            Section("Monthly Plan") {
                if viewModel.hasSavedPlan {
                    LabeledContent("Status", value: viewModel.isPlanExpired ? "Review due" : "Active")
                    LabeledContent("Days Left", value: "\(viewModel.planDaysRemaining)")

                    if let planEndDate = viewModel.planEndDate {
                        LabeledContent("Ends", value: planEndDate.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    Text("No workout plan yet.")
                        .foregroundColor(.secondary)
                }
            }

            Section("Water Reminders") {
                DatePicker(
                    "Wake-up time",
                    selection: $hydrationWakeTime,
                    displayedComponents: .hourAndMinute
                )
            }

            Section {
                Button(viewModel.hasSavedPlan ? "Change Plan" : "Build Plan") {
                    isChangingPlan = true
                    viewModel.beginPlanSetup()
                }
            }

            Section {
                Button("Logout", role: .destructive) {
                    session.logout()
                }
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
        .onAppear {
            hydrationWakeTime = HydrationReminderSettings.wakeTimeDate()
        }
        .onChange(of: hydrationWakeTime) { _, newValue in
            HydrationReminderSettings.saveWakeTime(newValue)
            Task {
                await waterViewModel.loadToday()
            }
        }
    }

    private func stopPlanChange() {
        guard isChangingPlan || viewModel.isSettingUpPlan else { return }

        isChangingPlan = false
        viewModel.cancelPlanSetup()
    }

    private func displayName(for user: UserAccount) -> String {
        guard let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "Not set"
        }

        return name
    }
}
