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

    // Time Attack clock
    @State private var endDate = Date.distantFuture
    @State private var remaining: TimeInterval = 0
    @State private var lastTickSecond = Int.max
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

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
        .sensoryFeedback(trigger: picked) { _, new in
            guard let new, let question = current else { return nil }
            return new == question.correctIndex ? .success : .error
        }
        .onAppear(perform: start)
        .onReceive(clock) { _ in tick() }
    }

    // MARK: - HUD

    private var hud: some View {
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
            Label("\(score)", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.green)
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
        .padding(.horizontal)
    }

    private var timerLabel: some View {
        let urgent = remaining <= 10
        return Label(timeString, systemImage: "timer")
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(urgent ? .red : .primary)
            .scaleEffect(urgent ? 1.08 : 1)
            .animation(.snappy(duration: 0.2), value: urgent)
    }

    private var timeString: String {
        let total = max(0, Int(remaining.rounded(.up)))
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
            remaining = TimeInterval(seconds)
        }
        loadNext()
    }

    private func tick() {
        guard case .timeAttack = mode, !finished else { return }
        remaining = endDate.timeIntervalSinceNow
        // clock "tick" haptic once per second over the final 10 (DESIGN.md §5)
        let second = Int(remaining.rounded(.up))
        if second != lastTickSecond, second <= 10, second > 0 {
            lastTickSecond = second
            Haptics.countdownTick()
        }
        if remaining <= 0 {
            finish()
        }
    }

    private func select(_ i: Int) {
        guard picked == nil, let question = current, !finished else { return }
        picked = i
        let correct = i == question.correctIndex
        streak = correct ? streak + 1 : 0
        let earned = ProgressionStore.recordAnswer(
            modelContext, data: data, question: question, correct: correct,
            difficulty: currentDifficulty, streak: correct ? streak - 1 : 0)
        xpEarned += earned
        answered.append(AnsweredQuestion(question: question, pickedIndex: i))
        if !correct {
            switch mode {
            case .timeAttack: endDate.addTimeInterval(-3)   // wrong = −3s
            case .survival: misses += 1
            }
        }
        // brief flash so the border colors register, longer on a miss so the
        // correct answer can be read before the next question slides in
        Task {
            try? await Task.sleep(for: .seconds(correct ? 0.6 : 1.2))
            advance()
        }
    }

    private func advance() {
        guard !finished else { return }
        if case .survival = mode, misses >= 3 {
            finish()
            return
        }
        picked = nil
        loadNext()
    }

    private func loadNext() {
        guard let next = QuizEngine.makeQuestion(data: data, difficulty: currentDifficulty,
                                                 excluding: usedSignatures) else {
            finish()
            return
        }
        usedSignatures.insert(next.signature)
        current = next
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
