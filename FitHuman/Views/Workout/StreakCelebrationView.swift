import SwiftUI

struct StreakCelebrationView: View {
    let startCount: Int
    let endCount: Int

    @State private var displayedCount: Int
    @State private var flameScale = 0.65
    @State private var flameRotation = -8.0
    @State private var haloScale = 0.75

    init(startCount: Int, endCount: Int) {
        self.startCount = startCount
        self.endCount = endCount
        _displayedCount = State(initialValue: startCount)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 150, height: 150)
                    .scaleEffect(haloScale)

                Circle()
                    .stroke(Color.green.opacity(0.45), lineWidth: 5)
                    .frame(width: 122, height: 122)
                    .scaleEffect(haloScale)

                Image(systemName: "flame.fill")
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(flameScale)
                    .rotationEffect(.degrees(flameRotation))
                    .shadow(color: .orange.opacity(0.55), radius: 20, x: 0, y: 10)
            }
            .frame(width: 168, height: 158)

            Text("Streak Updated")
                .font(.headline.bold())
                .foregroundColor(.green)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(displayedCount)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .contentTransition(.numericText())

                Text(displayedCount == 1 ? "day" : "days")
                    .font(.title3.bold())
                    .foregroundColor(.secondary)
            }
            .monospacedDigit()
        }
        .padding(.vertical, 8)
        .task {
            await playAnimation()
        }
    }

    private func playAnimation() async {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            flameScale = 1.08
            haloScale = 1.02
            flameRotation = 6
        }

        try? await Task.sleep(nanoseconds: 260_000_000)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
            flameScale = 1
            flameRotation = 0
        }

        await countToEndValue()

        withAnimation(.easeInOut(duration: 0.9).repeatCount(2, autoreverses: true)) {
            haloScale = 1.14
            flameScale = 1.08
        }
    }

    private func countToEndValue() async {
        guard displayedCount != endCount else {
            return
        }

        let step = displayedCount < endCount ? 1 : -1
        var nextValue = displayedCount + step

        while true {
            try? await Task.sleep(nanoseconds: 180_000_000)

            withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
                displayedCount = nextValue
                flameScale = 1.16
                haloScale = 1.08
            }

            try? await Task.sleep(nanoseconds: 90_000_000)

            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                flameScale = 1
                haloScale = 1
            }

            if nextValue == endCount {
                break
            }

            nextValue += step
        }
    }
}
