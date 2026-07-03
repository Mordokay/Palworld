import SwiftUI
import SwiftData

/// Answered-question record for the results review list.
struct AnsweredQuestion: Identifiable {
    let id = UUID()
    let question: Question
    let pickedIndex: Int
    var wasCorrect: Bool { pickedIndex == question.correctIndex }
}

struct QuizView: View {
    let data: GameData
    let difficulty: Difficulty
    let categoryLabel: String
    /// Set when replaying a saved session: XP only for not-yet-green questions.
    let replayOf: QuizSession?
    /// QuizSession.mode for history ("quick", "daily", "wheel", "whosthatpal"...).
    let sessionMode: String
    /// Daily Challenge day key ("2026-07-03"); stamps the session for streaks.
    let dailyKey: String
    /// Called once with the full answer sheet when the session is saved
    /// (Placement Test scores its tiers here).
    let onFinish: (([AnsweredQuestion]) -> Void)?

    /// Held as @State: parents re-evaluate their navigationDestination closures
    /// on every re-render (answers write to SwiftData → @Query updates), and a
    /// plain `let` would swap the questions mid-session.
    @State private var questions: [Question]

    init(data: GameData, questions: [Question], difficulty: Difficulty,
         categoryLabel: String = "Pals", replayOf: QuizSession? = nil,
         resume: ActiveQuiz? = nil, sessionMode: String = "quick",
         dailyKey: String = "", onFinish: (([AnsweredQuestion]) -> Void)? = nil) {
        self.data = data
        self.difficulty = difficulty
        self.categoryLabel = categoryLabel
        self.replayOf = replayOf
        self.sessionMode = sessionMode
        self.dailyKey = dailyKey
        self.onFinish = onFinish
        _questions = State(initialValue: questions)
        if let resume {
            let restored = zip(resume.questions.indices, resume.pickedIndexes).map {
                AnsweredQuestion(question: resume.questions[$0.0], pickedIndex: $0.1)
            }
            _answered = State(initialValue: restored)
            _index = State(initialValue: resume.pickedIndexes.count)
            _xpEarned = State(initialValue: resume.xpEarned)
            _streak = State(initialValue: resume.streak)
        }
    }

    @Environment(\.modelContext) private var modelContext
    @State private var index = 0
    @State private var picked: Int?
    @State private var answered: [AnsweredQuestion] = []
    @State private var infoArticleID: String?
    @State private var streak = 0
    @State private var xpEarned = 0
    @State private var saved = false

    var body: some View {
        Group {
            if index < questions.count {
                questionScreen(questions[index])
            } else {
                QuizResultsView(data: data, answered: answered, xpEarned: xpEarned)
                    .onAppear(perform: saveSession)
            }
        }
        .navigationBarBackButtonHidden(index < questions.count && index > 0)
        .sensoryFeedback(trigger: picked) { _, new in
            guard let new, index < questions.count else { return nil }
            return new == questions[index].correctIndex ? .success : .error
        }
        .sheet(item: $infoArticleID) { id in
            ArticleSheetView(data: data, articleID: id)
        }
    }

    private func saveSession() {
        guard !saved, !answered.isEmpty else { return }
        saved = true
        // XP pays out only on completion
        ProgressionStore.profile(modelContext).xp += xpEarned
        for record in (try? modelContext.fetch(FetchDescriptor<ActiveQuiz>())) ?? [] {
            modelContext.delete(record)
        }
        let score = answered.filter(\.wasCorrect).count
        if let replay = replayOf {
            for (i, entry) in answered.enumerated() where i < replay.everCorrect.count {
                replay.lastCorrect[i] = entry.wasCorrect
                replay.everCorrect[i] = replay.everCorrect[i] || entry.wasCorrect
            }
            replay.bestScore = max(replay.bestScore, score)
            replay.xpEarned += xpEarned
            replay.date = .now
        } else {
            let session = QuizSession()
            session.mode = sessionMode
            session.dayKey = dailyKey
            session.categoryLabel = categoryLabel
            session.difficulty = difficulty.rawValue
            session.signatures = answered.map(\.question.signature)
            session.lastCorrect = answered.map(\.wasCorrect)
            session.everCorrect = answered.map(\.wasCorrect)
            session.bestScore = score
            session.xpEarned = xpEarned
            modelContext.insert(session)
        }
        onFinish?(answered)
    }

    private func questionScreen(_ question: Question) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(index), total: Double(questions.count))
                .tint(.purple)

            Text("Question \(index + 1) of \(questions.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                QuestionCardView(question: question, picked: picked, select: select)
                    .padding(.horizontal)
            }

            if picked != nil {
                HStack(spacing: 12) {
                    if question.articleID != nil {
                        Button {
                            infoArticleID = question.articleID
                        } label: {
                            Label("Learn more", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        advance(question)
                    } label: {
                        Text(index + 1 == questions.count ? "Finish" : "Next")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private func select(_ i: Int) {
        guard picked == nil, index < questions.count else { return }
        picked = i
        let question = questions[index]
        let correct = i == question.correctIndex
        streak = correct ? streak + 1 : 0
        // replays only pay XP for questions that have never been green
        let paysXP = replayOf.map { session in
            index < session.everCorrect.count && !session.everCorrect[index]
        } ?? true
        let earned = ProgressionStore.recordAnswer(
            modelContext, data: data, question: question, correct: correct,
            difficulty: difficulty, streak: correct ? streak - 1 : 0)
        if paysXP {
            xpEarned += earned
        }
        // create/refresh the save-state on the very first pick so the
        // "Continue quiz" card exists immediately, not only after Next
        persistProgress()
    }

    private func advance(_ question: Question) {
        if let picked {
            answered.append(AnsweredQuestion(question: question, pickedIndex: picked))
        }
        picked = nil
        index += 1
        persistProgress()
    }

    /// Save-state after every answer so a killed app (or tab hop) can resume.
    private func persistProgress() {
        guard index < questions.count else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<ActiveQuiz>())) ?? []
        let record = existing.first ?? {
            let fresh = ActiveQuiz()
            modelContext.insert(fresh)
            return fresh
        }()
        for extra in existing.dropFirst() {
            modelContext.delete(extra)
        }
        record.date = .now
        record.mode = sessionMode
        record.dayKey = dailyKey
        record.categoryLabel = categoryLabel
        record.difficulty = difficulty.rawValue
        record.questionsData = (try? JSONEncoder().encode(questions)) ?? Data()
        record.pickedIndexes = answered.map(\.pickedIndex)
        record.xpEarned = xpEarned
        record.streak = streak
        record.replaySessionUUID = replayOf?.uuid
    }
}

// sheet(item:) needs Identifiable
extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// The prompt + answer options for one question — shared by the untimed
/// QuizView and the arcade modes (Time Attack, Survival).
struct QuestionCardView: View {
    let question: Question
    let picked: Int?
    let select: (Int) -> Void

    /// Subtle per-position tints (Kahoot-style) so the four cards read apart at a glance.
    private static let positionTints: [Color] = [.blue, .red, .orange, .purple]

    var body: some View {
        VStack(spacing: 20) {
            if let file = question.promptImageFile {
                promptImage(file)
            }
            Text(question.promptText)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            optionsView
        }
    }

    /// Silhouette questions render the pal solid black on a spotlight card,
    /// then fade to the real artwork the moment an answer is picked.
    @ViewBuilder
    private func promptImage(_ file: String) -> some View {
        let silhouette = question.isSilhouette == true
        let hidden = silhouette && picked == nil
        WikiImage(file: file, kind: question.imageKind)
            .colorMultiply(hidden ? .black : .white)
            .frame(height: 180)
            .padding(silhouette ? 14 : 0)
            .background {
                if silhouette {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [.indigo.opacity(0.45), .purple.opacity(0.25)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .animation(.easeInOut(duration: 0.5), value: hidden)
    }

    @ViewBuilder
    private var optionsView: some View {
        let isImageChoice = question.options.contains { $0.imageFile != nil }
        if isImageChoice {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                    Button { select(i) } label: {
                        VStack(spacing: 6) {
                            WikiImage(file: option.imageFile ?? "", kind: question.imageKind)
                                .frame(height: question.showOptionLabels ? 105 : 130)
                                .frame(maxWidth: .infinity)
                            if question.showOptionLabels {
                                Text(option.text)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .padding(8)
                        .background(optionBackground(i),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(optionBorder(i), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                    Button { select(i) } label: {
                        Text(option.text)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(optionBackground(i),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(optionBorder(i), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Soft fill — kept gentle because pal images are transparent and the
    /// background shows through them; the border carries the state.
    private func optionBackground(_ i: Int) -> Color {
        if let picked {
            if i == question.correctIndex { return .green.opacity(0.14) }
            if i == picked { return .red.opacity(0.14) }
        }
        let option = question.options[i]
        let tint = option.tintElement.map(Theme.elementColor)
            ?? Self.positionTints[i % Self.positionTints.count]
        return tint.opacity(picked == nil ? 0.12 : 0.05)
    }

    private func optionBorder(_ i: Int) -> Color {
        guard let picked else { return .clear }
        if i == question.correctIndex { return .green.opacity(0.85) }
        if i == picked { return .red.opacity(0.85) }
        return .clear
    }
}

struct QuizResultsView: View {
    let data: GameData
    let answered: [AnsweredQuestion]
    let xpEarned: Int
    @State private var infoArticleID: String?
    @State private var expanded: Set<UUID> = []

    private var correctCount: Int { answered.filter(\.wasCorrect).count }
    private var xp: Int { xpEarned }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("\(correctCount)/\(answered.count)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Label("+\(xp) XP", systemImage: Theme.Stat.xp.symbol)
                        .font(.headline)
                        .foregroundStyle(Theme.Stat.xp.color)
                    Text(verdict)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Review") {
                ForEach(answered) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: entry.wasCorrect
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(entry.wasCorrect ? .green : .red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.question.promptText.components(separatedBy: "\n").first ?? "")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(entry.wasCorrect
                                     ? entry.question.correctOption.text
                                     : "Correct: \(entry.question.correctOption.text) — you picked \(entry.question.options[entry.pickedIndex].text)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded.contains(entry.id) ? 180 : 0))
                            if let articleID = entry.question.articleID {
                                Button {
                                    infoArticleID = articleID
                                } label: {
                                    Image(systemName: "book.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if expanded.contains(entry.id) {
                                expanded.remove(entry.id)
                            } else {
                                expanded.insert(entry.id)
                            }
                        }
                        // kept in the hierarchy at height 0 so expansion
                        // animates as smooth growth + fade, not an insertion
                        ReviewQuestionDetail(entry: entry)
                            .padding(.top, 10)
                            .frame(height: expanded.contains(entry.id) ? nil : 0,
                                   alignment: .top)
                            .clipped()
                            .opacity(expanded.contains(entry.id) ? 1 : 0)
                    }
                    .animation(.snappy(duration: 0.3), value: expanded)
                }
            }
        }
        .navigationTitle("Results")
        .sheet(item: $infoArticleID) { id in
            ArticleSheetView(data: data, articleID: id)
        }
    }

    private var verdict: String {
        let ratio = answered.isEmpty ? 0 : Double(correctCount) / Double(answered.count)
        switch ratio {
        case 1: return "Perfect! Pal Professor material."
        case 0.8...: return "Great run!"
        case 0.5...: return "Solid — check the review below."
        default: return "The Library awaits. Tap the books to study."
        }
    }
}

/// Expanded review row: the full question with every option, your pick and
/// the correct answer marked just like in the live quiz.
struct ReviewQuestionDetail: View {
    let entry: AnsweredQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let file = entry.question.promptImageFile {
                WikiImage(file: file, kind: entry.question.imageKind)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
            }
            if entry.question.promptText.contains("\n") {
                Text(entry.question.promptText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.question.options.enumerated()), id: \.offset) { i, option in
                HStack(spacing: 8) {
                    if let imageFile = option.imageFile {
                        WikiImage(file: imageFile, kind: entry.question.imageKind)
                            .frame(width: 30, height: 30)
                    }
                    Text(option.text)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if i == entry.question.correctIndex {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if i == entry.pickedIndex {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(rowBackground(i), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(rowBorder(i), lineWidth: 2))
            }
        }
        .padding(.bottom, 6)
    }

    private func rowBackground(_ i: Int) -> Color {
        if i == entry.question.correctIndex { return .green.opacity(0.10) }
        if i == entry.pickedIndex { return .red.opacity(0.10) }
        return Color(.secondarySystemBackground)
    }

    private func rowBorder(_ i: Int) -> Color {
        if i == entry.question.correctIndex { return .green.opacity(0.7) }
        if i == entry.pickedIndex { return .red.opacity(0.7) }
        return .clear
    }
}
