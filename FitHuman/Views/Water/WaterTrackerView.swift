import SwiftUI
import Combine

struct WaterTrackerView: View {
    @ObservedObject var viewModel: WaterViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isManualAmountFocused: Bool
    @State private var manualAmountText = ""

    private let dayCheckTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var palette: WaterPalette {
        WaterPalette(colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                header
                pastSevenDays
                bottleSection
                todayIntake
                quickAddButton
                customEntry

                if viewModel.isLoading {
                    ProgressView()
                        .tint(palette.accent)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .background(palette.pageBackground.ignoresSafeArea())
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.checkMidnightReset()
            }
        }
        .onReceive(dayCheckTimer) { _ in
            viewModel.checkMidnightReset()
        }
        .task {
            await viewModel.loadToday()
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isManualAmountFocused = false
                }
            }
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Water Tracker")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 10)

            AverageBadge(value: formattedML(viewModel.averageIntakeML), palette: palette)
        }
    }

    private var pastSevenDays: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Past 7 Days")
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.primaryText)

            HStack(spacing: 7) {
                if viewModel.historyDays.isEmpty {
                    ForEach(0..<7, id: \.self) { _ in
                        EmptyWaterHistoryBubble(palette: palette)
                    }
                } else {
                    ForEach(viewModel.historyDays) { day in
                        WaterHistoryBubble(day: day, palette: palette)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bottleSection: some View {
        LargeWaterBottle(progress: viewModel.progress, palette: palette)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var todayIntake: some View {
        VStack(spacing: 8) {
            Text("Today's Intake")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.secondaryText)

            Text("\(formattedML(viewModel.currentIntakeML)) / \(formattedML(viewModel.dailyGoalML))")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(remainingText)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(palette.accentSoft)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var quickAddButton: some View {
        Button {
            viewModel.addGlass()
        } label: {
            Label("Add 250 mL", systemImage: "drop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WaterPrimaryButtonStyle(palette: palette))
    }

    private var customEntry: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                manualAmountField

                Text("mL")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            .background(palette.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isManualAmountFocused ? palette.accent : palette.border, lineWidth: 1)
            )

            Button {
                addManualAmount()
            } label: {
                Label("Add custom water", systemImage: "plus")
                    .font(.headline.weight(.bold))
                    .labelStyle(.iconOnly)
                    .frame(width: 52, height: 52)
            }
            .disabled(manualAmountML == nil)
            .foregroundStyle(.white)
            .background(manualAmountML == nil ? palette.disabledControl : palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Add custom water amount")
        }
    }

    @ViewBuilder
    private var manualAmountField: some View {
        #if os(iOS)
        TextField("Custom amount", text: $manualAmountText)
            .keyboardType(.decimalPad)
            .focused($isManualAmountFocused)
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.primaryText)
        #else
        TextField("Custom amount", text: $manualAmountText)
            .focused($isManualAmountFocused)
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.primaryText)
        #endif
    }

    private var manualAmountML: Double? {
        let normalized = manualAmountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else {
            return nil
        }

        return amount
    }

    private var remainingText: String {
        let remaining = max(viewModel.dailyGoalML - viewModel.currentIntakeML, 0)
        if remaining == 0 {
            return "Daily goal reached"
        }

        return "\(formattedML(remaining)) left"
    }

    private func addManualAmount() {
        guard let amount = manualAmountML else {
            return
        }

        viewModel.addWater(amountML: amount)
        manualAmountText = ""
        isManualAmountFocused = false
    }

    private func formattedML(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded.formatted()) mL"
    }
}

private struct AverageBadge: View {
    let value: String
    let palette: WaterPalette

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.accent)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text("Avg Intake")
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(minWidth: 118)
        .background(palette.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct LargeWaterBottle: View {
    let progress: Double
    let palette: WaterPalette
    @State private var bubblesAreFloating = false

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(palette.bottleGlass)
                .frame(width: 166, height: 362)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 31, style: .continuous)
                    .fill(palette.bottleInterior)

                waterFill

                bubbleLayer
            }
            .frame(width: 150, height: 344)
            .clipShape(RoundedRectangle(cornerRadius: 31, style: .continuous))

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(palette.bottleOutline, lineWidth: 5)
                .frame(width: 166, height: 362)
        }
        .frame(height: 372)
        .onAppear {
            bubblesAreFloating = true
        }
        .accessibilityHidden(true)
    }

    private var waterFill: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            LinearGradient(
                colors: [palette.teal.opacity(0.86), palette.accent.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 150, height: 344 * clampedProgress)
            .animation(.easeInOut(duration: 0.8), value: clampedProgress)
        }
    }

    private var bubbleLayer: some View {
        ZStack {
            FloatingBubble(
                xOffset: -42,
                lowerYOffset: 98,
                upperYOffset: -108,
                size: 9,
                delay: 0.0,
                isFloating: bubblesAreFloating,
                palette: palette
            )

            FloatingBubble(
                xOffset: 38,
                lowerYOffset: 78,
                upperYOffset: -128,
                size: 12,
                delay: 0.45,
                isFloating: bubblesAreFloating,
                palette: palette
            )

            FloatingBubble(
                xOffset: 4,
                lowerYOffset: 116,
                upperYOffset: -92,
                size: 7,
                delay: 0.9,
                isFloating: bubblesAreFloating,
                palette: palette
            )

            FloatingBubble(
                xOffset: -18,
                lowerYOffset: 54,
                upperYOffset: -146,
                size: 10,
                delay: 1.2,
                isFloating: bubblesAreFloating,
                palette: palette
            )
        }
        .opacity(clampedProgress > 0.04 ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: clampedProgress)
    }
}

private struct FloatingBubble: View {
    let xOffset: CGFloat
    let lowerYOffset: CGFloat
    let upperYOffset: CGFloat
    let size: CGFloat
    let delay: Double
    let isFloating: Bool
    let palette: WaterPalette

    var body: some View {
        Circle()
            .stroke(palette.bubble, lineWidth: 1.8)
            .background(Circle().fill(.white.opacity(0.08)))
            .frame(width: size, height: size)
            .offset(x: xOffset, y: isFloating ? upperYOffset : lowerYOffset)
            .scaleEffect(isFloating ? 1.18 : 0.72)
            .opacity(isFloating ? 0.0 : 0.92)
            .animation(
                .easeOut(duration: 2.4)
                    .delay(delay)
                    .repeatForever(autoreverses: false),
                value: isFloating
            )
    }
}

private struct WaterPrimaryButtonStyle: ButtonStyle {
    let palette: WaterPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(
                    colors: [palette.accent, palette.teal],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

private struct WaterHistoryBubble: View {
    let day: WaterHistoryDay
    let palette: WaterPalette

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                Circle()
                    .stroke(palette.historyOutline, lineWidth: 2)

                if let progress = day.progress {
                    Rectangle()
                        .fill(palette.accent)
                        .frame(height: 34 * min(max(progress, 0), 1))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            Text(day.shortDayText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 36)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityText)
    }
}

private struct EmptyWaterHistoryBubble: View {
    let palette: WaterPalette

    var body: some View {
        VStack(spacing: 7) {
            Circle()
                .stroke(palette.historyOutline, lineWidth: 2)
                .frame(width: 34, height: 34)

            Text(" ")
                .font(.caption2)
                .frame(width: 36)
        }
        .accessibilityHidden(true)
    }
}

private struct WaterPalette {
    let pageBackground: Color
    let cardBackground: Color
    let elevatedSurface: Color
    let fieldBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let border: Color
    let bottleGlass: Color
    let bottleInterior: Color
    let bottleOutline: Color
    let historyOutline: Color
    let accent: Color
    let teal: Color
    let accentSoft: Color
    let disabledControl: Color
    let bubble: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            pageBackground = Color(red: 0.02, green: 0.06, blue: 0.07)
            cardBackground = Color(red: 0.06, green: 0.11, blue: 0.14)
            elevatedSurface = Color(red: 0.08, green: 0.15, blue: 0.19)
            fieldBackground = Color(red: 0.03, green: 0.08, blue: 0.10)
            primaryText = .white
            secondaryText = Color.white.opacity(0.66)
            border = Color.white.opacity(0.09)
            bottleGlass = Color(red: 0.10, green: 0.20, blue: 0.25).opacity(0.42)
            bottleInterior = Color(red: 0.04, green: 0.10, blue: 0.13).opacity(0.85)
            bottleOutline = Color(red: 0.58, green: 0.80, blue: 0.96).opacity(0.66)
            historyOutline = Color(red: 0.58, green: 0.80, blue: 0.96).opacity(0.52)
            accent = Color(red: 0.23, green: 0.58, blue: 1.0)
            teal = Color(red: 0.22, green: 0.83, blue: 0.90)
            accentSoft = Color(red: 0.12, green: 0.32, blue: 0.45).opacity(0.55)
            disabledControl = Color.white.opacity(0.18)
            bubble = Color.white.opacity(0.72)
        } else {
            pageBackground = Color(red: 0.94, green: 0.98, blue: 1.0)
            cardBackground = .white
            elevatedSurface = Color(red: 0.90, green: 0.96, blue: 1.0)
            fieldBackground = Color(red: 0.98, green: 0.995, blue: 1.0)
            primaryText = Color(red: 0.06, green: 0.12, blue: 0.16)
            secondaryText = Color(red: 0.43, green: 0.51, blue: 0.57)
            border = Color(red: 0.78, green: 0.89, blue: 0.95)
            bottleGlass = Color(red: 0.88, green: 0.96, blue: 1.0).opacity(0.78)
            bottleInterior = Color(red: 0.97, green: 0.995, blue: 1.0)
            bottleOutline = Color(red: 0.55, green: 0.78, blue: 0.94)
            historyOutline = Color(red: 0.67, green: 0.82, blue: 0.92)
            accent = Color(red: 0.08, green: 0.45, blue: 0.95)
            teal = Color(red: 0.10, green: 0.74, blue: 0.84)
            accentSoft = Color(red: 0.88, green: 0.96, blue: 1.0)
            disabledControl = Color(red: 0.74, green: 0.80, blue: 0.84)
            bubble = Color.white.opacity(0.86)
        }
    }
}

private extension WaterHistoryDay {
    var shortDayText: String {
        guard let date = Self.dayFormatter.date(from: day) else {
            return day
        }

        return Self.shortFormatter.string(from: date)
    }

    var accessibilityText: String {
        guard let currentIntakeML else {
            return "\(shortDayText), no water data"
        }

        return "\(shortDayText), \(Int(currentIntakeML.rounded())) milliliters"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}
