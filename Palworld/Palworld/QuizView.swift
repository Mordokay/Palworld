import SwiftUI

/// Answered-question record for the results review list.
struct AnsweredQuestion: Identifiable {
    let id = UUID()
    let question: Question
    let pickedIndex: Int
    var wasCorrect: Bool { pickedIndex == question.correctIndex }
}

struct QuizView: View {
    let data: GameData
    let questions: [Question]
    let difficulty: Difficulty

    @State private var index = 0
    @State private var picked: Int?
    @State private var answered: [AnsweredQuestion] = []
    @State private var infoArticleID: String?

    var body: some View {
        Group {
            if index < questions.count {
                questionScreen(questions[index])
            } else {
                QuizResultsView(data: data, answered: answered, difficulty: difficulty)
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

    private func questionScreen(_ question: Question) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(index), total: Double(questions.count))
                .tint(.purple)

            Text("Question \(index + 1) of \(questions.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 20) {
                    if let file = question.promptImageFile {
                        WikiImage(file: file, kind: question.imageKind)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text(question.promptText)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)

                    optionsView(question)
                }
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

    /// Subtle per-position tints (Kahoot-style) so the four cards read apart at a glance.
    private static let positionTints: [Color] = [.blue, .red, .orange, .purple]

    @ViewBuilder
    private func optionsView(_ question: Question) -> some View {
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
                        .background(optionBackground(i, question: question),
                                    in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(picked != nil)
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
                            .background(optionBackground(i, question: question),
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(picked != nil)
                }
            }
        }
    }

    private func optionBackground(_ i: Int, question: Question) -> Color {
        if let picked {
            if i == question.correctIndex { return .green.opacity(0.35) }
            if i == picked { return .red.opacity(0.35) }
        }
        let option = question.options[i]
        let tint = option.tintElement.map(Theme.elementColor)
            ?? Self.positionTints[i % Self.positionTints.count]
        return tint.opacity(picked == nil ? 0.12 : 0.05)
    }

    private func select(_ i: Int) {
        guard picked == nil else { return }
        picked = i
    }

    private func advance(_ question: Question) {
        if let picked {
            answered.append(AnsweredQuestion(question: question, pickedIndex: picked))
        }
        picked = nil
        index += 1
    }
}

// sheet(item:) needs Identifiable
extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct QuizResultsView: View {
    let data: GameData
    let answered: [AnsweredQuestion]
    let difficulty: Difficulty
    @State private var infoArticleID: String?

    private var correctCount: Int { answered.filter(\.wasCorrect).count }
    private var xp: Int {
        let base = answered.filter(\.wasCorrect).map(\.question.baseXP).reduce(0, +)
        return Int(Double(base) * difficulty.xpMultiplier)
    }

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
                        if let articleID = entry.question.articleID {
                            Button {
                                infoArticleID = articleID
                            } label: {
                                Image(systemName: "book.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
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
