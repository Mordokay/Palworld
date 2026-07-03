import UIKit

/// App-wide haptics. Answer feedback lives on the quiz view via
/// `.sensoryFeedback` (.success / .error); this helper covers cases that need
/// imperative triggering.
enum Haptics {
    private static let tickGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Short clock "tick" for timed modes: call once per second during the
    /// final 10 seconds of a fixed-time quiz (DESIGN.md §5 Time Attack).
    static func countdownTick() {
        tickGenerator.impactOccurred(intensity: 0.6)
        tickGenerator.prepare()
    }
}
