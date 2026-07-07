import SwiftUI

struct PlanSetupView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    let title: String
    let subtitle: String
    let buttonTitle: String
    var prefillsExistingProfile = true
    var onPlanGenerated: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var weightText = ""
    @State private var heightText = ""
    @State private var selectedGoal: FitnessGoal = .bodyRecomposition
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section {
                Text(title)
                    .font(.largeTitle.bold())
                    .listRowSeparator(.hidden)

                Text(subtitle)
                    .foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
            }

            Section("Body") {
                weightField
                heightField
            }

            Section("Goal") {
                Picker("Goal", selection: $selectedGoal) {
                    ForEach(FitnessGoal.allCases) { goal in
                        Text(goal.rawValue).tag(goal)
                    }
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .foregroundColor(.red)
            }

            if let generationError = viewModel.generationErrorMessage {
                Text(generationError)
                    .foregroundColor(.red)
            }

            Section {
                VStack(spacing: 12) {
                    Button {
                        submitProfile()
                    } label: {
                        if viewModel.isGeneratingPlan {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(buttonTitle)
                        }
                    }
                    .disabled(viewModel.isGeneratingPlan)
                    .buttonStyle(PrimaryButtonStyle())

                    if viewModel.hasSavedPlan && viewModel.isSettingUpPlan {
                        Button {
                            viewModel.cancelPlanSetup()
                            onCancel?()
                        } label: {
                            Text("Keep Current Plan")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        .background(Color.secondary.opacity(0.14))
                        .cornerRadius(16)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .onAppear(perform: prefillProfileIfNeeded)
    }

    @ViewBuilder
    private var weightField: some View {
        #if os(iOS)
        TextField("Weight (kg)", text: $weightText)
            .keyboardType(.decimalPad)
        #else
        TextField("Weight (kg)", text: $weightText)
        #endif
    }

    @ViewBuilder
    private var heightField: some View {
        #if os(iOS)
        TextField("Height (cm)", text: $heightText)
            .keyboardType(.decimalPad)
        #else
        TextField("Height (cm)", text: $heightText)
        #endif
    }

    private func prefillProfileIfNeeded() {
        guard prefillsExistingProfile,
              let profile = viewModel.userProfile else { return }

        weightText = String(format: "%.0f", profile.weightKg)
        heightText = String(format: "%.0f", profile.heightCm)
        selectedGoal = profile.goal
    }

    private func submitProfile() {
        guard let weight = Double(weightText), weight > 0 else {
            validationMessage = "Enter a valid weight in kg."
            return
        }

        guard let height = Double(heightText), height > 0 else {
            validationMessage = "Enter a valid height in cm."
            return
        }

        validationMessage = nil

        let profile = UserFitnessProfile(
            weightKg: weight,
            heightCm: height,
            goal: selectedGoal
        )

        Task {
            await viewModel.generatePlan(profile: profile)

            await MainActor.run {
                if viewModel.generationErrorMessage == nil && viewModel.hasSavedPlan {
                    onPlanGenerated?()
                }
            }
        }
    }
}
