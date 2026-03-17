import SwiftUI

/// 旋转图标 — spinning 时持续旋转，停止时立即定格
struct SpinningIcon: View {
    let systemName: String
    let isSpinning: Bool

    var body: some View {
        if isSpinning {
            TimelineView(.animation) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let angle = seconds.truncatingRemainder(dividingBy: 1) * 360
                Image(systemName: systemName)
                    .rotationEffect(.degrees(angle))
            }
        } else {
            Image(systemName: systemName)
        }
    }
}
