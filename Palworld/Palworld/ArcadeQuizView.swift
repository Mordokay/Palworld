import Combine
import SwiftUI
import SwiftData

/// The two endless "arcade" modes (DESIGN.md §5). Questions stream one at a
/// time and auto-advance after a short feedback flash — no Next button.
enum ArcadeMode: Hashable {
    /// Fixed clock, max correct answers; a wrong answer costs 3 seconds.
    case timeAttack(seconds: Int)
    /// 3 lives, difficulty ramps every 10 correct; score = questions survived.
    case survival

    var sessionMode: String {
        switch self {
        case .timeAttack: "timeAttack"
        case .survival: "survival"
        }
    }

    var categoryLabel: String {
        switch self {
        case .timeAttack(let seconds): "Time Attack · \(Self.durationLabel(seconds))"
        case .survival: "Survival"
        }
    }

    static func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}

struct ArcadeQuizView: View {
    let data: GameData
    let mode: ArcadeMode
    /// Chosen difficulty for Time Attack; Survival ignores it and ramps.
    let difficulty: Difficulty

    @Environment(\.modelContext) private var modelContext
    @State private var current: Question?
    @State private var picked: Int?
    @State private var answered: [AnsweredQuestion] = []
    @State private var usedSignatures: Set<String> = []
    @State private var streak = 0
    @State private var xpEarned = 0
    @State private var misses = 0
    @State private var finished = false
    @State private var saved = false

    // Time Attack clock. The countdown display lives in a TimelineView and
    // the tick bookkeeping in a reference box: neither touches @State, so the
    // 10 Hz clock never re-renders the question card (which reloads its
    // option images from disk on every body pass — instant-tap killer).
    @State private var endDate = Date.distantFuture
    /// Non-nil while the clock is frozen for the answer-feedback window.
    @State private var pausedRemaining: TimeInterval?
    private final class TickBox { var lastSecond = Int.max }
    private let tickBox = TickBox()
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// Fixed feedback window between answer and next question.
    private static let feedbackSeconds = 1.0

    private var score: Int { answered.filter(\.wasCorrect).count }

    /// Survival ramps every 10 correct: easy → medium → hard.
    private var currentDifficulty: Difficulty {
        switch mode {
        case .timeAttack: difficulty
        case .survival: score < 10 ? .easy : score < 20 ? .medium : .hard
        }
    }

    var body: some View {
        Group {
            if finished {
                QuizResultsView(data: data, answered: answered, xpEarned: xpEarned)
            } else if let question = current {
                VStack(spacing: 12) {
                    hud
                    ScrollView {
                        QuestionCardView(question: question, picked: picked, select: select)
                            .equatable()
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(mode.categoryLabel)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!finished && !answered.isEmpty)
        .onAppear(perform: start)
        .onReceive(clock) { _ in tick() }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                switch mode {
                case .timeAttack:
                    timerLabel
                case .survival:
                    livesLabel
                    difficultyBadge
                }
                Spacer()
                if streak >= 3 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                }
                Button {
                    finish()
                } label: {
                    Image(systemName: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
            }
            if !answered.isEmpty {
                shotRow
            }
        }
        .padding(.horizontal)
    }

    /// Penalty-shootout strip: one green/red dot per answered question
    /// (the most recent 15 — the full sheet is in the results review).
    private var shotRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(answered.suffix(15).enumerated()), id: \.offset) { _, entry in
                Circle()
                    .fill(entry.wasCorrect ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            }
            Spacer()
        }
        .animation(.snappy(duration: 0.25), value: answered.count)
    }

    private var timerLabel: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let left = pausedRemaining ?? max(0, endDate.timeIntervalSinceNow)
            let urgent = left <= 10
            Label(timeString(left),
                  systemImage: pausedRemaining == nil ? "timer" : "pause.circle.fill")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(urgent ? .red : .primary)
        }
    }

    private func timeString(_ left: TimeInterval) -> String {
        let total = max(0, Int(left.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var livesLabel: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < 3 - misses ? "heart.fill" : "heart.slash")
                    .foregroundStyle(i < 3 - misses ? .red : .secondary)
            }
        }
        .font(.headline)
    }

    private var difficultyBadge: some View {
        Text(currentDifficulty.label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(difficultyColor.opacity(0.15), in: Capsule())
            .foregroundStyle(difficultyColor)
    }

    private var difficultyColor: Color {
        switch currentDifficulty {
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        }
    }

    // MARK: - Flow

    private func start() {
        guard current == nil, !finished else { return }
        if case .timeAttack(let seconds) = mode {
            endDate = Date().addingTimeInterval(TimeInterval(seconds))
        }
        loadNext()
    }

    private func tick() {
        guard case .timeAttack = mode, !finished, pausedRemaining == nil else { return }
        let left = endDate.timeIntervalSinceNow
        // clock "tick" haptic once per second over the final 10 (DESIGN.md §5)
        let second = Int(left.rounded(.up))
        if second != tickBox.lastSecond, second <= 10, second > 0 {
            tickBox.lastSecond = second
            Haptics.countdownTick()
        }
        if left <= 0 {
            finish()
        }
    }

    private func select(_ i: Int) {
        guard picked == nil, let question = current, !finished else { return }
        // haptic + paint first: only cheap state here, everything else waits
        let correct = i == question.correctIndex
        Haptics.answer(correct: correct)
        picked = i
        streak = correct ? streak + 1 : 0
        answered.append(AnsweredQuestion(question: question, pickedIndex: i))
        switch mode {
        case .timeAttack:
            // freeze the clock for the feedback window; a wrong answer takes
            // its −3s bite visibly, right when the red border shows
            pausedRemaining = max(0, endDate.timeIntervalSinceNow - (correct ? 0 : 3))
        case .survival:
            if !correct { misses += 1 }
        }
        Task {
            // SwiftData bookkeeping after the answer state is on screen
            try? await Task.sleep(for: .milliseconds(50))
            xpEarned += ProgressionStore.recordAnswer(
                modelContext, data: data, question: question, correct: correct,
                difficulty: currentDifficulty, streak: correct ? streak - 1 : 0)
            try? await Task.sleep(for: .seconds(Self.feedbackSeconds - 0.05))
            advance()
        }
    }

    private func advance() {
        guard !finished else { return }
        if case .survival = mode, misses >= 3 {
            finish()
            return
        }
        if let frozen = pausedRemaining {
            if frozen <= 0 {
                finish()
                return
            }
            // resume the clock exactly where the feedback window froze it
            endDate = Date().addingTimeInterval(frozen)
            pausedRemaining = nil
        }
        picked = nil
        loadNext()
    }

    @State private var prefetched: Question?

    private func loadNext() {
        guard let next = prefetched ?? QuizEngine.makeQuestion(
            data: data, difficulty: currentDifficulty, excluding: usedSignatures) else {
            finish()
            return
        }
        usedSignatures.insert(next.signature)
        current = next
        // line up the following question and warm its images off-main so the
        // next advance renders without disk IO
        prefetched = QuizEngine.makeQuestion(data: data, difficulty: currentDifficulty,
                                             excluding: usedSignatures)
        if let prefetched {
            WikiImage.warm(prefetched)
        }
    }

    /// Ends the run (clock out, 3rd life lost, or the flag button) — arcade
    /// runs always pay out because reaching the end IS finishing.
    private func finish() {
        guard !finished else { return }
        finished = true
        guard !saved, !answered.isEmpty else { return }
        saved = true
        ProgressionStore.profile(modelContext).xp += xpEarned
        let session = QuizSession()
        session.mode = mode.sessionMode
        session.categoryLabel = mode.categoryLabel
        session.difficulty = currentDifficulty.rawValue
        session.signatures = answered.map(\.question.signature)
        session.lastCorrect = answered.map(\.wasCorrect)
        session.everCorrect = answered.map(\.wasCorrect)
        session.bestScore = score
        session.xpEarned = xpEarned
        modelContext.insert(session)
    }
}

/// Duration + difficulty picker for Time Attack; rules card for Survival.
struct TimeAttackSetupView: View {
    let data: GameData
    @State private var seconds = 60
    @State private var difficulty: Difficulty = .medium

    var body: some View {
        Form {
            Section("Duration") {
                Picker("Duration", selection: $seconds) {
                    ForEach([30, 60, 300, 600], id: \.self) {
                        Text(ArcadeMode.durationLabel($0)).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Difficulty") {
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(Difficulty.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                NavigationLink("Start") {
                    ArcadeQuizView(data: data, mode: .timeAttack(seconds: seconds),
                                   difficulty: difficulty)
                }
                .font(.headline)
            } footer: {
                Text("Answer as many as you can before the clock runs out. Wrong answers cost 3 seconds!")
            }
        }
        .navigationTitle("Time Attack")
    }
}

struct SurvivalSetupView: View {
    let data: GameData

    var body: some View {
        Form {
            Section {
                Label("You have 3 lives — a wrong answer breaks a heart", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                Label("Difficulty ramps up every 10 correct answers", systemImage: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.orange)
                Label("Score = questions survived", systemImage: "trophy.fill")
                    .foregroundStyle(.yellow)
            }
            Section {
                NavigationLink("Start") {
                    ArcadeQuizView(data: data, mode: .survival, difficulty: .easy)
                }
                .font(.headline)
            }
        }
        .navigationTitle("Survival")
    }
}
