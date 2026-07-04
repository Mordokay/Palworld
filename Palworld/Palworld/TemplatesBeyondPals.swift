import Foundation

// Question templates over items, weapons, skills and game mechanics
// (DESIGN.md §4 catalog #16–35). Subjects are item/skill/element ids, so
// signatures replay through the same pipeline as pal questions.

// MARK: - Item helpers

private func quizItems(_ data: GameData) -> [Item] {
    // items + weapons share the Item shape; stable order for seeded RNG
    (data.items + data.weapons).filter { $0.name.count > 1 }
}

private func itemSubject(_ data: GameData, _ subjectID: String?,
                         pool: [Item], rng: SeededRNG) -> Item? {
    subjectID.flatMap { data.itemByID[$0] } ?? pool.randomElement(seeded: rng)
}

/// Same-type distractors on hard — knowing an item's look-alikes is the lever.
private func itemDistractors(for answer: Item, pool: [Item], difficulty: Difficulty,
                             rng: SeededRNG) -> [Item] {
    var candidates = pool.filter { $0.id != answer.id && $0.name != answer.name }
    if difficulty == .hard {
        let similar = candidates.filter { $0.type == answer.type }
        if similar.count >= 3 { candidates = similar }
    }
    return Array(candidates.shuffled(seeded: rng).prefix(3))
}

struct IconToItemTemplate: QuestionTemplate {
    let id = "item.icon"
    let facet = "identify"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = quizItems(data).filter { GameData.imageURL($0.image, kind: .items) != nil }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              GameData.imageURL(item.image, kind: .items) != nil else { return nil }
        let wrong = itemDistractors(for: item, pool: pool, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: item, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name)
        }
        var question = Question(
            templateID: id, promptText: "What item is this?", promptImageFile: item.image,
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items"], baseXP: 10
        )
        question.imageKind = .items
        return question
    }
}

struct RecipeToItemTemplate: QuestionTemplate {
    let id = "item.recipe"
    let facet = "crafting"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = quizItems(data).filter { $0.craftMaterials.count >= 2 }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              item.craftMaterials.count >= 2 else { return nil }
        let recipe = item.craftMaterials.joined(separator: "  +  ")
        let wrong = itemDistractors(for: item, pool: pool, difficulty: difficulty, rng: rng)
        guard wrong.count == 3 else { return nil }
        func icon(_ candidate: Item) -> String? {
            GameData.imageURL(candidate.image, kind: .items) != nil ? candidate.image : nil
        }
        let allIcons = ([item] + wrong).allSatisfy { icon($0) != nil }
        let (options, correctIndex) = mcOptions(correct: item, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: allIcons ? icon($0) : nil)
        }
        var question = Question(
            templateID: id,
            promptText: "Which item does this recipe craft?\n\n\(recipe)",
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

struct ItemMaterialTemplate: QuestionTemplate {
    let id = "item.material"
    let facet = "crafting"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = quizItems(data).filter { !$0.craftMaterials.isEmpty }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              !item.craftMaterials.isEmpty,
              let material = item.craftMaterials.randomElement(seeded: rng)
        else { return nil }
        let answer = GameData.strippedName(material)
        let mine = Set(item.craftMaterials.map { GameData.strippedName($0).lowercased() })
        let others = Set(pool.flatMap { $0.craftMaterials.map(GameData.strippedName) })
            .filter { !mine.contains($0.lowercased()) }
        let wrong = Array(others.sorted().shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        func icon(_ name: String) -> String? {
            data.resolveEntityName(name).flatMap { data.itemByID[$0]?.image }
                .flatMap { GameData.imageURL($0, kind: .items) != nil ? $0 : nil }
        }
        let allIcons = ([answer] + wrong).allSatisfy { icon($0) != nil }
        let (options, correctIndex) = mcOptions(correct: answer, distractors: wrong, rng: rng) {
            QuizOption(text: $0, imageFile: allIcons ? icon($0) : nil)
        }
        var question = Question(
            templateID: id,
            promptText: "Which of these is needed to craft \(item.name)?",
            promptImageFile: item.image,
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

struct TechTierTemplate: QuestionTemplate {
    let id = "item.techTier"
    let facet = "tech"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = quizItems(data).filter { ($0.techTier ?? 0) > 0 }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              let tier = item.techTier else { return nil }
        // neighbours make plausible wrong answers; hard = adjacent tiers
        let spread = difficulty == .hard ? [-2, -1, 1, 2, 3] : [-15, -8, -4, 4, 8, 15]
        var wrong: Set<Int> = []
        for delta in spread.shuffled(seeded: rng) where wrong.count < 3 {
            let candidate = tier + delta
            if candidate >= 1, candidate <= 55, candidate != tier {
                wrong.insert(candidate)
            }
        }
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: tier, distractors: Array(wrong),
                                                rng: rng) {
            QuizOption(text: "Level \($0)")
        }
        var question = Question(
            templateID: id,
            promptText: "At what technology level is \(item.name) unlocked?",
            promptImageFile: item.image,
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

struct RarityTemplate: QuestionTemplate {
    let id = "item.rarity"
    let facet = "rarity"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = quizItems(data).filter { !$0.rarity.isEmpty }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              !item.rarity.isEmpty else { return nil }
        let allRarities = Set(pool.map(\.rarity)).subtracting([item.rarity])
        let wrong = Array(allRarities.sorted().shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: item.rarity, distractors: wrong,
                                                rng: rng) {
            QuizOption(text: $0)
        }
        var question = Question(
            templateID: id, promptText: "What rarity is \(item.name)?",
            promptImageFile: item.image,
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items"], baseXP: 10
        )
        question.imageKind = .items
        return question
    }
}

// MARK: - Skill templates

struct SkillElementTemplate: QuestionTemplate {
    let id = "skill.element"
    let facet = "element"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.skills.filter { !$0.element.isEmpty }
        guard let skill = subjectID.flatMap({ data.skillByID[$0] })
            ?? pool.randomElement(seeded: rng), !skill.element.isEmpty else { return nil }
        let wrong = Array(Theme.allElements.filter {
            $0.caseInsensitiveCompare(skill.element) != .orderedSame
        }.shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let answer = skill.element.capitalized
        let (options, correctIndex) = mcOptions(correct: answer, distractors: wrong,
                                                rng: rng) {
            QuizOption(text: $0, tintElement: $0)
        }
        return Question(
            templateID: id,
            promptText: "What element is the skill “\(skill.name)”?",
            options: options, correctIndex: correctIndex,
            articleID: skill.id, subjectID: skill.id, facet: facet,
            categoryIDs: ["skills", "element:\(answer)"], baseXP: 10
        )
    }
}

struct DescriptionToSkillTemplate: QuestionTemplate {
    let id = "skill.description"
    let facet = "identify"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.skills.filter { $0.description.count > 30 }
        guard let skill = subjectID.flatMap({ data.skillByID[$0] })
            ?? pool.randomElement(seeded: rng),
            skill.description.count > 30 else { return nil }
        var candidates = pool.filter { $0.id != skill.id }
        if difficulty == .hard {
            let similar = candidates.filter { $0.element == skill.element }
            if similar.count >= 3 { candidates = similar }
        }
        let wrong = Array(candidates.shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let masked = skill.description.replacingOccurrences(of: skill.name, with: "???")
        let (options, correctIndex) = mcOptions(correct: skill, distractors: wrong,
                                                rng: rng) {
            QuizOption(text: $0.name, tintElement: $0.element.isEmpty ? nil : $0.element)
        }
        return Question(
            templateID: id,
            promptText: "Which skill is this?\n\n“\(masked)”",
            options: options, correctIndex: correctIndex,
            articleID: skill.id, subjectID: skill.id, facet: facet,
            categoryIDs: ["skills"], baseXP: 15
        )
    }
}

// MARK: - Buildings (the "big building template" is the group:
// QuizEngine.buildingTemplates draws one sub-template at random)

/// Cleans a farmingProduce list: drops "Rank N:" headers, strips quantities.
private func ranchProduce(_ pal: Pal) -> [String] {
    pal.farmingProduce
        .filter { !$0.hasSuffix(":") }
        .map { $0.replacingOccurrences(of: #"\s*x[\d\-]+$"#, with: "",
                                       options: .regularExpression) }
        .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
}

struct RanchProduceTemplate: QuestionTemplate {
    let id = "building.ranchProduce"
    let facet = "utility"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.quizPals.filter { !ranchProduce($0).isEmpty }
        guard let pal = subjectID.flatMap({ data.palByID[$0] })
            ?? pool.randomElement(seeded: rng),
            let answer = ranchProduce(pal).randomElement(seeded: rng) else { return nil }
        let mine = Set(ranchProduce(pal).map { $0.lowercased() })
        let others = Set(pool.flatMap(ranchProduce)).filter { !mine.contains($0.lowercased()) }
        let wrong = Array(others.sorted().shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        func icon(_ name: String) -> String? {
            data.resolveEntityName(name).flatMap { data.itemByID[$0]?.image }
                .flatMap { GameData.imageURL($0, kind: .items) != nil ? $0 : nil }
        }
        let allIcons = ([answer] + wrong).allSatisfy { icon($0) != nil }
        let (options, correctIndex) = mcOptions(correct: answer, distractors: wrong, rng: rng) {
            QuizOption(text: $0, imageFile: allIcons ? icon($0) : nil)
        }
        var question = Question(
            templateID: id,
            promptText: "What does \(pal.name) produce when assigned to the Ranch?",
            promptImageFile: pal.image,
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal) + ["buildings"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

struct RanchProducerTemplate: QuestionTemplate {
    let id = "building.ranchProducer"
    let facet = "utility"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.quizPals.filter { !ranchProduce($0).isEmpty }
        guard let pal = subjectID.flatMap({ data.palByID[$0] })
            ?? pool.randomElement(seeded: rng),
            let produce = ranchProduce(pal).randomElement(seeded: rng) else { return nil }
        // distractors must NOT produce the asked item at the ranch
        let producers = Set(pool.filter { ranchProduce($0).contains(produce) }.map(\.id))
        let wrong = Array(data.quizPalsWithImage.filter { !producers.contains($0.id) }
            .shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: pal, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id,
            promptText: "Which of these pals produces \(produce) at the Ranch?",
            options: options, correctIndex: correctIndex,
            articleID: pal.id, subjectID: pal.id, facet: facet,
            categoryIDs: palCategories(pal) + ["buildings"], baseXP: 15
        )
    }
}

/// Feed-box knowledge: which of four foods fills the most hunger. 88 foods
/// carry nutrition values, so the combinations are effectively endless.
struct NutritionPickTemplate: QuestionTemplate {
    let id = "building.nutrition"
    let facet = "nutrition"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.items.filter { ($0.nutrition ?? 0) > 0 }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              let winning = item.nutrition else { return nil }
        var lower = pool.filter { ($0.nutrition ?? .max) < winning }
        guard lower.count >= 3 else { return nil }
        if difficulty == .hard {
            lower.sort { ($0.nutrition ?? 0) > ($1.nutrition ?? 0) }
            lower = Array(lower.prefix(8))
        }
        let wrong = Array(lower.shuffled(seeded: rng).prefix(3))
        func icon(_ candidate: Item) -> String? {
            GameData.imageURL(candidate.image, kind: .items) != nil ? candidate.image : nil
        }
        let allIcons = ([item] + wrong).allSatisfy { icon($0) != nil }
        let (options, correctIndex) = mcOptions(correct: item, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name, imageFile: allIcons ? icon($0) : nil)
        }
        var question = Question(
            templateID: id,
            promptText: "Which of these foods is the most filling?",
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items", "buildings"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

struct TechPointsTemplate: QuestionTemplate {
    let id = "building.techPoints"
    let facet = "tech"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.technology.filter { $0.structure && $0.points > 0 && !$0.ancient }
        guard let tech = subjectID.flatMap({ id in pool.first { $0.subjectID == id } })
            ?? pool.randomElement(seeded: rng) else { return nil }
        // wrong answers drawn from point costs that actually exist in the tree
        let values = Set(pool.map(\.points)).subtracting([tech.points]).sorted {
            abs($0 - tech.points) < abs($1 - tech.points)
        }
        let candidates = difficulty == .hard ? Array(values.prefix(5)) : values
        let wrong = Array(candidates.shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: tech.points, distractors: wrong,
                                                rng: rng) {
            QuizOption(text: "\($0) point\($0 == 1 ? "" : "s")")
        }
        var question = Question(
            templateID: id,
            promptText: "How many Technology Points does the \(tech.name) cost to unlock?",
            promptImageFile: tech.image,
            options: options, correctIndex: correctIndex,
            articleID: data.idByName[tech.name.lowercased()],
            subjectID: tech.subjectID, facet: facet,
            categoryIDs: ["technology", "buildings"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

struct AncientTechTemplate: QuestionTemplate {
    let id = "building.ancientTech"
    let facet = "tech"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let ancients = data.technology.filter { $0.ancient }
        let normals = data.technology.filter { !$0.ancient && $0.points > 0 }
        guard let tech = subjectID.flatMap({ id in ancients.first { $0.subjectID == id } })
            ?? ancients.randomElement(seeded: rng) else { return nil }
        let wrong = Array(normals.shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: tech, distractors: wrong, rng: rng) {
            QuizOption(text: $0.name)
        }
        return Question(
            templateID: id,
            promptText: "Which of these requires Ancient Technology Points to unlock?",
            options: options, correctIndex: correctIndex,
            articleID: data.idByName[tech.name.lowercased()],
            subjectID: tech.subjectID, facet: facet,
            categoryIDs: ["technology", "buildings"], baseXP: 15
        )
    }
}

/// Materials question scoped to base structures (workbenches, furnaces...).
struct BuildingMaterialTemplate: QuestionTemplate {
    let id = "building.material"
    let facet = "crafting"

    static let buildingTypes: Set<String> = [
        "Production", "Infrastructure", "Foundations", "Defenses",
        "Storage", "Lighting", "Furniture",
    ]

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.items.filter {
            Self.buildingTypes.contains($0.type) && !$0.craftMaterials.isEmpty
        }
        guard let item = itemSubject(data, subjectID, pool: pool, rng: rng),
              !item.craftMaterials.isEmpty,
              let material = item.craftMaterials.randomElement(seeded: rng)
        else { return nil }
        let answer = GameData.strippedName(material)
        let mine = Set(item.craftMaterials.map { GameData.strippedName($0).lowercased() })
        let others = Set(pool.flatMap { $0.craftMaterials.map(GameData.strippedName) })
            .filter { !mine.contains($0.lowercased()) }
        let wrong = Array(others.sorted().shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        func icon(_ name: String) -> String? {
            data.resolveEntityName(name).flatMap { data.itemByID[$0]?.image }
                .flatMap { GameData.imageURL($0, kind: .items) != nil ? $0 : nil }
        }
        let allIcons = ([answer] + wrong).allSatisfy { icon($0) != nil }
        let (options, correctIndex) = mcOptions(correct: answer, distractors: wrong, rng: rng) {
            QuizOption(text: $0, imageFile: allIcons ? icon($0) : nil)
        }
        var question = Question(
            templateID: id,
            promptText: "Which material do you need to build the \(item.name)?",
            promptImageFile: item.image,
            options: options, correctIndex: correctIndex,
            articleID: item.id, subjectID: item.id, facet: facet,
            categoryIDs: ["items", "buildings"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

// MARK: - World & mechanics

struct ElementEffectivenessTemplate: QuestionTemplate {
    let id = "world.effectiveness"
    let facet = "elements"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let defender = subjectID?.capitalized
            ?? Theme.allElements.randomElement(seeded: rng) ?? "Water"
        // exactly one element hits each defender for 1.5× (wiki chart)
        guard let strong = Theme.damageTaken[defender.lowercased()]?
            .first(where: { $0.value > 1 })?.key.capitalized else { return nil }
        let wrong = Array(Theme.allElements.filter {
            $0 != strong && $0 != defender
        }.shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: strong, distractors: wrong,
                                                rng: rng) {
            QuizOption(text: $0, tintElement: $0)
        }
        let articleID = defender.lowercased()
        return Question(
            templateID: id,
            promptText: "Which element deals extra damage to \(defender) pals?",
            options: options, correctIndex: correctIndex,
            articleID: data.articleByID[articleID] != nil ? articleID : nil,
            subjectID: articleID, facet: facet,
            categoryIDs: ["elements", "element:\(defender)"], baseXP: 15
        )
    }
}

/// Which pal lives at a location — sanctuaries and strongholds have curated
/// inhabitant lists on the wiki.
struct LocationInhabitantTemplate: QuestionTemplate {
    let id = "world.inhabitant"
    let facet = "geography"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        // locations whose inhabitants resolve to actual pals
        func residents(_ location: Location) -> [Pal] {
            location.inhabitants.compactMap {
                data.idByName[$0.lowercased()].flatMap { data.palByID[$0] }
            }
        }
        let pool = data.locations.filter { residents($0).count >= 2 }
        guard let location = subjectID.flatMap({ id in pool.first { $0.id == id } })
            ?? pool.randomElement(seeded: rng) else { return nil }
        let locals = residents(location)
        guard let answer = locals.randomElement(seeded: rng) else { return nil }
        let localIDs = Set(locals.map(\.id))
        let wrong = Array(data.quizPalsWithImage.filter { !localIDs.contains($0.id) }
            .shuffled(seeded: rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: answer, distractors: wrong,
                                                rng: rng) {
            QuizOption(text: $0.name, imageFile: $0.image)
        }
        return Question(
            templateID: id,
            promptText: "Which of these pals can be found at \(location.name)?",
            options: options, correctIndex: correctIndex,
            articleID: data.articleByID[location.id] != nil ? location.id : nil,
            subjectID: location.id, facet: facet,
            categoryIDs: ["world"], baseXP: 15
        )
    }
}

/// Buildings & structures from the tech tree: at what level do they unlock?
struct TechUnlockTemplate: QuestionTemplate {
    let id = "world.techUnlock"
    let facet = "tech"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        let pool = data.technology.filter { $0.structure }
        guard let tech = subjectID.flatMap({ id in pool.first { $0.subjectID == id } })
            ?? pool.randomElement(seeded: rng) else { return nil }
        let spread = difficulty == .hard ? [-2, -1, 1, 2, 3] : [-15, -8, -4, 4, 8, 15]
        var wrong: Set<Int> = []
        for delta in spread.shuffled(seeded: rng) where wrong.count < 3 {
            let candidate = tech.level + delta
            if candidate >= 1, candidate <= 60, candidate != tech.level {
                wrong.insert(candidate)
            }
        }
        guard wrong.count == 3 else { return nil }
        let (options, correctIndex) = mcOptions(correct: tech.level,
                                                distractors: Array(wrong), rng: rng) {
            QuizOption(text: "Level \($0)")
        }
        var question = Question(
            templateID: id,
            promptText: "At what technology level can you build the \(tech.name)?",
            promptImageFile: tech.image,
            options: options, correctIndex: correctIndex,
            articleID: data.idByName[tech.name.lowercased()],
            subjectID: tech.subjectID, facet: facet,
            categoryIDs: ["technology"], baseXP: 15
        )
        question.imageKind = .items
        return question
    }
}

/// Hand-curated Millionaire-style lore & guides trivia (data/trivia.json):
/// the Guides & World articles are prose, so their questions are pre-written
/// offline and bundled — no generation at runtime, no AI in the app.
struct TriviaTemplate: QuestionTemplate {
    let id = "world.trivia"
    let facet = "lore"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        guard !data.trivia.isEmpty else { return nil }
        let matching = data.trivia.filter { $0.difficulty == difficulty.rawValue }
        let pool = matching.isEmpty ? data.trivia : matching
        guard let entry = subjectID.flatMap({ id in data.trivia.first { $0.id == id } })
            ?? pool.randomElement(seeded: rng) else { return nil }
        let (options, correctIndex) = mcOptions(correct: entry.answer,
                                                distractors: entry.wrong, rng: rng) {
            QuizOption(text: $0)
        }
        return Question(
            templateID: id, promptText: entry.q,
            options: options, correctIndex: correctIndex,
            articleID: entry.articleID.flatMap { data.articleByID[$0] != nil ? $0 : nil },
            subjectID: entry.id, facet: facet,
            categoryIDs: ["world"], baseXP: 15
        )
    }
}

/// True/False fact flips (catalog #34) — pal facts across facets, two options.
struct TrueFalsePalTemplate: QuestionTemplate {
    let id = "pal.trueFalse"
    let facet = "lore"

    func generate(data: GameData, difficulty: Difficulty, rng: SeededRNG,
                  subjectID: String?) -> Question? {
        guard let pal = subjectID.flatMap({ data.palByID[$0] })
            ?? data.quizPals.randomElement(seeded: rng) else { return nil }
        let truth = rng.next() % 2 == 0

        var statement: String?
        var factFacet = facet
        switch rng.next() % 3 {
        case 0 where !pal.elements.isEmpty:
            factFacet = "elements"
            let real = pal.elements[0]
            let element = truth ? real
                : Theme.allElements.filter { !pal.elements.contains($0) }
                    .randomElement(seeded: rng) ?? real
            statement = "\(pal.name) is a \(element)-type."
        case 1 where !pal.workSuitability.isEmpty:
            factFacet = "work"
            let works = Set(pal.workSuitability.keys)
            let all = Set(data.quizPals.flatMap { $0.workSuitability.keys })
            let work = truth ? works.sorted().randomElement(seeded: rng)
                : all.subtracting(works).sorted().randomElement(seeded: rng)
            guard let work else { return nil }
            statement = "\(pal.name) is suited for \(Theme.workLabel(work)) work."
        case 2 where !pal.drops.isEmpty:
            factFacet = "drops"
            let mine = Set(pal.drops.map { GameData.strippedName($0).lowercased() })
            let drop = truth ? pal.drops.randomElement(seeded: rng).map(GameData.strippedName)
                : Set(data.quizPals.flatMap { $0.drops.map(GameData.strippedName) })
                    .filter { !mine.contains($0.lowercased()) }
                    .sorted().randomElement(seeded: rng)
            guard let drop else { return nil }
            statement = "\(pal.name) drops \(drop)."
        default:
            return nil
        }
        guard let statement else { return nil }

        return Question(
            templateID: id,
            promptText: "True or false?\n\n\(statement)",
            promptImageFile: pal.image,
            options: [QuizOption(text: "True"), QuizOption(text: "False")],
            correctIndex: truth ? 0 : 1,
            articleID: pal.id, subjectID: pal.id, facet: factFacet,
            categoryIDs: palCategories(pal), baseXP: 8
        )
    }
}
