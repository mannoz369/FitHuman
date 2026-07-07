import SwiftUI
import Combine

struct RestTimerView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var restRemaining: Int = 20
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Rest")
                .font(.largeTitle).bold()
            
            Text("\(restRemaining)")
                .font(.system(size: 100, weight: .heavy, design: .monospaced))
                .onReceive(timer) { _ in
                    if restRemaining > 0 {
                        restRemaining -= 1
                    } else {
                        viewModel.nextExercise()
                    }
                }
            
            HStack(spacing: 20) {
                Button("+10 Sec") { restRemaining += 10 }
                    .buttonStyle(SecondaryButtonStyle())
                Button("+20 Sec") { restRemaining += 20 }
                    .buttonStyle(SecondaryButtonStyle())
            }
            
            Button("Skip Rest") { viewModel.nextExercise() }
                .foregroundColor(.red)
                .padding(.top, 20)
        }
        .onAppear {
            restRemaining = viewModel.currentExercise?.rest_seconds ?? 20
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
    }
}
