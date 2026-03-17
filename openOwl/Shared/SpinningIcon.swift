import SwiftUI

/// 旋转图标 — spinning 时持续旋转，停止时立即定格（不反转）
struct SpinningIcon: View {
    let systemName: String
    let isSpinning: Bool

    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: systemName)
            .rotationEffect(.degrees(angle))
            .onChange(of: isSpinning) { _, spinning in
                if spinning {
                    startSpinning()
                } else {
                    stopSpinning()
                }
            }
            .onAppear {
                if isSpinning { startSpinning() }
            }
    }

    private func startSpinning() {
        angle = 0
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }

    private func stopSpinning() {
        // Replace repeatForever with a zero-duration animation to halt immediately
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            angle = angle.truncatingRemainder(dividingBy: 360)
        }
    }
}
