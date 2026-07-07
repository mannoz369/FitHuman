import SwiftUI

struct StreakLabel: View {
    let currentStreak: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(currentStreak)")
            Image(systemName: "flame.fill")
                .imageScale(.medium)
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }
}
