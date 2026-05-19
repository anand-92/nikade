import SwiftUI

/// Spinning icon — rotates continuously when isSpinning is true, stays still otherwise.
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
