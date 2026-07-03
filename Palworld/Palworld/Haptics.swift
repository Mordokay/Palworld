import UIKit

/// App-wide haptics, triggered imperatively from tap handlers.
enum Haptics {
    private static let tickGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let answerGenerator = UINotificationFeedbackGenerator()

    /// Short clock "tick" for timed modes: call once per second during the
    /// final 10 seconds of a fixed-time quiz (DESIGN.md §5 Time Attack).
    static func countdownTick() {
        tickGenerator.impactOccurred(intensity: 0.6)
        tickGenerator.prepare()
    }

    /// Answer feedback, fired from the tap handler so it lands with the
    /// touch — `.sensoryFeedback` waits for the state's render, and under
    /// load (arcade modes) that frame can arrive noticeably later.
    static func answer(correct: Bool) {
        answerGenerator.notificationOccurred(correct ? .success : .error)
        answerGenerator.prepare()
    }
}
