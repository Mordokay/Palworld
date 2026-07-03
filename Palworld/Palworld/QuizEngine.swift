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

struct QuizOption: Hashable, Codable {
    var text: String
    var imageFile: String?
    /// Element name whose Theme color subtly tints this option's card.
    var tintElement: String?
}

/// One generated question. M2 supports multiple choice (text or image options);
/// further formats land with later milestones.
struct Question: Identifiable, Codable {
    var id = UUID()
    let templateID: String
    let promptText: String
    var promptImageFile: String?
    var imageKind: GameData.ImageKind = .pals
    let options: [QuizOption]
    let correctIndex: Int
    /// Hide labels when the text would give the answer away (name → picture).
    var showOptionLabels = true
    /// Render the prompt image as a black silhouette until answered
    /// ("Who's that Pal?"). Optional so pre-M5 saved quizzes still decode.
    var isSilhouette: Bool?
    /// Library page for the info button and results review.
    let articleID: String?
    /// Entity the question is about (dedupe within a session; XP routing).
    let subjectID: String
    /// Knowledge facet this exercises (DESIGN.md §7): identify, elements, lore...
    let facet: String
    /// Progression categories this routes XP to ("element:Water", "pals").
    let categoryIDs: [String]
    let baseXP: Int

    /// Stable identity for Smart Review / redemption / replay.
    var signature: String { "\(templateID)|\(subjectID)" }

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
    var facet: String { get }
    /// Generate one question, or nil if the data/rng draw can't support it.
    /// `subject` pins the question to a specific pal (targeted quizzes, replay).
    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question?
}

extension QuestionTemplate {
    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG) -> Question? {
        generate(data: data, difficulty: difficulty, rng: rng, subject: nil)
    }
}

func palCategories(_ pal: Pal) -> [String] {
    ["pals"] + pal.elements.map { "element:\($0)" }
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
    for answer: Pal, data: GameData, difficulty: Difficulty, rng: SeededRNG, count: Int = 3,
    requireImage: Bool = false
) -> [Pal] {
    // Difficulty lever = distractor similarity (DESIGN.md §6): hard prefers
    // pals sharing an element with the answer; easy draws from everyone.
    var pool = (requireImage ? data.quizPalsWithImage : data.quizPals)
        .filter { $0.id != answer.id }
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
    let facet = "identify"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question? {
        let pool = data.quizPalsWithImage
        guard let pal = subject ?? pool.randomElement(seeded: rng),
              GameData.imageURL(pal.image, kind: .pals) != nil else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name)
        }
        return Question(
            templateID: id, promptText: "Which pal is this?", promptImageFile: pal.image,
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal), baseXP: 10
        )
    }
}

struct NameToPictureTemplate: QuestionTemplate {
    let id = "pal.nameToPicture"
    let facet = "identify"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question? {
        // every option shows a picture — all four pals need bundled images
        let pool = data.quizPalsWithImage
        guard let pal = subject ?? pool.randomElement(seeded: rng),
              GameData.imageURL(pal.image, kind: .pals) != nil else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng,
                                   requireImage: true)
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id, promptText: "Which of these is \(pal.name)?",
            options: options, correctIndex: correctIndex, showOptionLabels: false,
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal), baseXP: 10
        )
    }
}

struct PalElementTemplate: QuestionTemplate {
    let id = "pal.element"
    let facet = "elements"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question? {
        guard let pal = subject ?? data.quizPals.filter({ !$0.elements.isEmpty })
            .randomElement(seeded: rng), !pal.elements.isEmpty else { return nil }
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
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal), baseXP: 10
        )
    }
}

struct LoreToPalTemplate: QuestionTemplate {
    let id = "pal.lore"
    let facet = "lore"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question? {
        // options render pal images — draw everyone from the with-image pool
        let pool = data.quizPalsWithImage.filter { $0.paldeckEntry.count > 40 }
        guard let pal = subject ?? pool.randomElement(seeded: rng),
              pal.paldeckEntry.count > 40 else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng,
                                   requireImage: true)
        guard wrong.count == 3 else { return nil }
        // the lore text sometimes names the pal — mask it out
        let lore = pal.paldeckEntry.replacingOccurrences(of: pal.name, with: "???")
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id, promptText: "Whose Paldeck entry is this?\n\n“\(lore)”",
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal), baseXP: 15
        )
    }
}

struct AlphaTitleTemplate: QuestionTemplate {
    let id = "pal.alphaTitle"
    let facet = "lore"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question? {
        // options render pal images — draw everyone from the with-image pool
        let titled = data.quizPalsWithImage.filter { !$0.alphaTitle.isEmpty }
        guard let pal = subject ?? titled.randomElement(seeded: rng),
              !pal.alphaTitle.isEmpty else { return nil }
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
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal), baseXP: 15
        )
    }
}

struct SilhouetteTemplate: QuestionTemplate {
    let id = "pal.silhouette"
    let facet = "identify"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subject: Pal?) -> Question? {
        // silhouettes need cutout artwork — opaque wiki screenshots black out
        // into a useless square
        let pool = data.silhouettePals
        guard let pal = subject ?? pool.randomElement(seeded: rng),
              GameData.imageURL(pal.image, kind: .pals) != nil else { return nil }
        let wrong = palDistractors(for: pal, data: data, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name)
        }
        var question = Question(
            templateID: id, promptText: "Who's that Pal?", promptImageFile: pal.image,
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal), baseXP: 15
        )
        question.isSilhouette = true
        return question
    }
}

// MARK: - Session builder

enum QuizEngine {
    /// General rotation for Quick Quiz & friends. Silhouettes stay out so the
    /// "Who's that Pal?" gimmick keeps its own mode fresh.
    static let palTemplates: [any QuestionTemplate] = [
        PictureToNameTemplate(), NameToPictureTemplate(), PalElementTemplate(),
        LoreToPalTemplate(), AlphaTitleTemplate(),
    ]

    /// Every template that can appear in a saved signature (replay lookup).
    static let allTemplates: [any QuestionTemplate] = palTemplates + [SilhouetteTemplate()]

    static var templateByID: [String: any QuestionTemplate] {
        Dictionary(uniqueKeysWithValues: allTemplates.map { ($0.id, $0) })
    }

    /// Build a session: `count` questions, subjects deduped (signatures when a
    /// small `subjects` pool forces repeats), consecutive templates differ.
    /// `templates` restricts the draw (Spin the Wheel, Who's that Pal?).
    static func makeSession(
        data: GameData, count: Int, difficulty: Difficulty, seed: UInt64? = nil,
        subjects: [Pal]? = nil, templates: [any QuestionTemplate]? = nil
    ) -> [Question] {
        let pool = templates ?? palTemplates
        let rng = seed.map(SeededRNG.init(seed:)) ?? SeededRNG()
        let smallPool = (subjects?.count ?? .max) < count
        var questions: [Question] = []
        var usedSubjects = Set<String>()
        var usedSignatures = Set<String>()
        var lastTemplate = ""
        var attempts = 0
        while questions.count < count && attempts < count * 40 {
            attempts += 1
            let template = pool[Int(rng.next() % UInt64(pool.count))]
            let subject = subjects?.randomElement(seeded: rng)
            guard template.id != lastTemplate || pool.count == 1,
                  let q = template.generate(data: data, difficulty: difficulty,
                                            rng: rng, subject: subject),
                  !usedSignatures.contains(q.signature),
                  smallPool || !usedSubjects.contains(q.subjectID)
            else { continue }
            usedSubjects.insert(q.subjectID)
            usedSignatures.insert(q.signature)
            lastTemplate = template.id
            questions.append(q)
        }
        return questions
    }

    /// One question at a time for endless modes (Time Attack, Survival):
    /// avoids `excluding` signatures while it can, recycles once the pool of
    /// fresh questions runs dry.
    static func makeQuestion(
        data: GameData, difficulty: Difficulty, excluding: Set<String>
    ) -> Question? {
        let rng = SeededRNG()
        for attempt in 0..<80 {
            let template = palTemplates[Int(rng.next() % UInt64(palTemplates.count))]
            guard let q = template.generate(data: data, difficulty: difficulty, rng: rng)
            else { continue }
            if attempt >= 60 || !excluding.contains(q.signature) { return q }
        }
        return nil
    }

    /// Rebuild a saved session's questions from signatures (history replay).
    /// Signature-based so it survives data refreshes; fresh distractors each time.
    static func regenerate(data: GameData, signatures: [String],
                           difficulty: Difficulty) -> [Question] {
        let rng = SeededRNG()
        let templates = templateByID
        return signatures.compactMap { signature in
            let parts = signature.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let template = templates[parts[0]],
                  let subject = data.palByID[parts[1]]
            else { return nil }
            return template.generate(data: data, difficulty: difficulty,
                                     rng: rng, subject: subject)
        }
    }
}
