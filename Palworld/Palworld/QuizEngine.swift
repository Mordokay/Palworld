import Foundation

// MARK: - Core quiz types (DESIGN.md §11)

enum Difficulty: String, CaseIterable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var xpMultiplier: Double {
        switch self {
        case .easy: 1
        case .medium: 1.5
        case .hard: 2
        }
    }
}

struct QuizOption: Hashable {
    var text: String
    var imageFile: String?
    /// Element name whose Theme color subtly tints this option's card.
    var tintElement: String?
}

/// One generated question. M2 supports multiple choice (text or image options);
/// further formats land with later milestones.
struct Question: Identifiable {
    let id = UUID()
    let templateID: String
    let promptText: String
    var promptImageFile: String?
    var imageKind: GameData.ImageKind = .pals
    let options: [QuizOption]
    let correctIndex: Int
    /// Hide labels when the text would give the answer away (name → picture).
    var showOptionLabels = true
    /// Library page for the info button and results review.
    let articleID: String?
    /// Entity the question is about (dedupe within a session; XP routing later).
    let subjectID: String
    let baseXP: Int

    var correctOption: QuizOption { options[correctIndex] }
}

/// Deterministic RNG (SplitMix64) so Daily Challenges replay identically.
final class SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }
    init() { state = UInt64.random(in: .min ... .max) }

    func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

protocol QuestionTemplate {
    var id: String { get }
    /// Generate one question, or nil if the data/rng draw can't support it.
    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question?
}

// RandomNumberGenerator APIs take the generator inout; these wrappers let the
// class-based SeededRNG flow through without inout plumbing at every call site.
extension Sequence {
    func shuffled(seeded rng: SeededRNG) -> [Element] {
        var g = rng
        return shuffled(using: &g)
    }
}

extension Collection {
    func randomElement(seeded rng: SeededRNG) -> Element? {
        var g = rng
        return randomElement(using: &g)
    }
}

// MARK: - Shared helpers

private func palDistractors(
    for answer: Pal, data: GameData, difficulty: Difficulty, rng: SeededRNG, count: Int = 3
) -> [Pal] {
    // Difficulty lever = distractor similarity (DESIGN.md §6): hard prefers
    // pals sharing an element with the answer; easy draws from everyone.
    var pool = data.quizPals.filter { $0.id != answer.id }
    if difficulty == .hard {
        let similar = pool.filter { !Set($0.elements).isDisjoint(with: answer.elements) }
        if similar.count >= count { pool = similar }
    }
    return Array(pool.shuffled(seeded: rng).prefix(count))
}

private func mcOptions<T>(
    correct: T, distractors: [T], rng: SeededRNG, label: (T) -> QuizOption
) -> (options: [QuizOption], correctIndex: Int) {
    var options = distractors.map(label)
    let index = Int(rng.next() % UInt64(options.count + 1))
    options.insert(label(correct), at: index)
    return (options, index)
}

// MARK: - Pal templates (catalog #1–6, MC formats)

struct PictureToNameTemplate: QuestionTemplate {
    let id = "pal.pictureToName"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question? {
        guard let pal = data.quizPals.randomElement(seeded: rng) else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name)
        }
        return Question(
            templateID: id, promptText: "Which pal is this?", promptImageFile: pal.image,
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, baseXP: 10
        )
    }
}

struct NameToPictureTemplate: QuestionTemplate {
    let id = "pal.nameToPicture"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question? {
        guard let pal = data.quizPals.randomElement(seeded: rng) else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id, promptText: "Which of these is \(pal.name)?",
            options: options, correctIndex: correctIndex, showOptionLabels: false,
            articleID: pal.id, subjectID: pal.id, baseXP: 10
        )
    }
}

struct PalElementTemplate: QuestionTemplate {
    let id = "pal.element"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question? {
        guard let pal = data.quizPals.filter({ !$0.elements.isEmpty })
            .randomElement(seeded: rng) else { return nil }
        let answer = pal.elements.joined(separator: " / ")
        let allCombos = Set(data.quizPals.map { $0.elements.joined(separator: " / ") })
            .subtracting([answer, ""])
        let wrong = Array(allCombos.sorted().shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: answer, distractors: wrong, rng: rng) {
            QuizOption(text: $0, tintElement: $0.components(separatedBy: " / ").first)
        }
        return Question(
            templateID: id, promptText: "What element type is \(pal.name)?",
            promptImageFile: difficulty == .easy ? pal.image : nil,
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, baseXP: 10
        )
    }
}

struct LoreToPalTemplate: QuestionTemplate {
    let id = "pal.lore"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question? {
        guard let pal = data.quizPals.filter({ $0.paldeckEntry.count > 40 })
            .randomElement(seeded: rng) else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        // the lore text sometimes names the pal — mask it out
        let lore = pal.paldeckEntry.replacingOccurrences(of: pal.name, with: "???")
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id, promptText: "Whose Paldeck entry is this?\n\n“\(lore)”",
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, baseXP: 15
        )
    }
}

struct AlphaTitleTemplate: QuestionTemplate {
    let id = "pal.alphaTitle"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question? {
        let titled = data.quizPals.filter { !$0.alphaTitle.isEmpty }
        guard let pal = titled.randomElement(seeded: rng) else { return nil }
        var pool = titled.filter { $0.id != pal.id }
        if difficulty == .hard {
            let similar = pool.filter { !Set($0.elements).isDisjoint(with: pal.elements) }
            if similar.count >= 3 { pool = similar }
        }
        let wrong = Array(pool.shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id,
            promptText: "Which pal bears the Alpha title “\(pal.alphaTitle)”?",
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, baseXP: 15
        )
    }
}

// MARK: - Session builder

enum QuizEngine {
    static let palTemplates: [any QuestionTemplate] = [
        PictureToNameTemplate(), NameToPictureTemplate(), PalElementTemplate(),
        LoreToPalTemplate(), AlphaTitleTemplate(),
    ]

    /// Build a session: `count` questions, no two about the same subject,
    /// consecutive questions from different templates where possible.
    static func makeSession(
        data: GameData, count: Int, difficulty: Difficulty, seed: UInt64? = nil
    ) -> [Question] {
        let rng = seed.map(SeededRNG.init(seed:)) ?? SeededRNG()
        var questions: [Question] = []
        var usedSubjects = Set<String>()
        var lastTemplate = ""
        var attempts = 0
        while questions.count < count && attempts < count * 30 {
            attempts += 1
            let template = palTemplates[Int(rng.next() % UInt64(palTemplates.count))]
            guard template.id != lastTemplate || palTemplates.count == 1,
                  let q = template.generate(data: data, difficulty: difficulty, rng: rng),
                  !usedSubjects.contains(q.subjectID)
            else { continue }
            usedSubjects.insert(q.subjectID)
            lastTemplate = template.id
            questions.append(q)
        }
        return questions
    }
}
