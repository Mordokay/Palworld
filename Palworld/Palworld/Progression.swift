import Foundation
import SwiftData
import SwiftUI

// MARK: - SwiftData models (DESIGN.md §7, §9)

@Model
final class PlayerProfile {
    var name: String = "Trainer"
    var avatarPalID: String = "lamball"
    var xp: Int = 0
    var preferredDifficulty: String = Difficulty.medium.rawValue
    var createdAt: Date = Date()

    init() {}
}

/// Per-entity, per-facet mastery counters. A facet is mastered at net +3.
@Model
final class FacetProgress {
    var entityID: String = ""
    var facet: String = ""
    var correctCount: Int = 0
    var missCount: Int = 0

    init(entityID: String, facet: String) {
        self.entityID = entityID
        self.facet = facet
    }

    var netCorrect: Int { max(0, correctCount - missCount) }
    var isMastered: Bool { netCorrect >= Progression.masteryThreshold }
}

/// XP earned per category (element categories, domains...).
@Model
final class CategoryXP {
    var categoryID: String = ""
    var xp: Int = 0

    init(categoryID: String) {
        self.categoryID = categoryID
    }
}

/// A question answered wrong and not yet redeemed — answering it correctly
/// later pays double XP (DESIGN.md redemption bonus).
@Model
final class MissRecord {
    var signature: String = ""
    var missedAt: Date = Date()
    var redeemed: Bool = false

    init(signature: String) {
        self.signature = signature
    }
}

/// A finished quiz. Signatures make it replayable forever; everCorrect powers
/// the completion ring (green once a question has EVER been answered right).
@Model
final class QuizSession {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var mode: String = "quick"
    var categoryLabel: String = "Pals"
    var difficulty: String = Difficulty.medium.rawValue
    /// "2026-07-03" for Daily Challenge sessions (immutable per session, so
    /// streaks survive `date` being touched by replays); empty otherwise.
    var dayKey: String = ""
    var signatures: [String] = []
    var lastCorrect: [Bool] = []
    var everCorrect: [Bool] = []
    var bestScore: Int = 0
    var xpEarned: Int = 0

    init() {}

    var completion: Double {
        everCorrect.isEmpty ? 0 : Double(everCorrect.filter { $0 }.count) / Double(everCorrect.count)
    }
}

/// The single in-progress quiz (non-timed modes): exact questions serialized
/// so resume shows identical options; replaced when a new quiz starts.
@Model
final class ActiveQuiz {
    var date: Date = Date()
    var mode: String = "quick"
    var dayKey: String = ""
    var categoryLabel: String = "Pals"
    var difficulty: String = Difficulty.medium.rawValue
    var questionsData: Data = Data()
    var pickedIndexes: [Int] = []
    var xpEarned: Int = 0
    var streak: Int = 0
    var replaySessionUUID: UUID?

    init() {}

    var questions: [Question] {
        (try? JSONDecoder().decode([Question].self, from: questionsData)) ?? []
    }
}

// MARK: - Level curve & facets

enum Progression {
    static let masteryThreshold = 3
    /// Facets current templates can exercise; grows with the template catalog.
    static let palFacets = ["identify", "elements", "lore"]

    /// XP needed to go from level n to n+1: 100 × 1.5^(n-1).
    static func xpForLevel(_ level: Int) -> Int {
        Int((100 * pow(1.5, Double(level - 1))).rounded())
    }

    /// (level, xp into current level, xp needed for next).
    static func level(forXP xp: Int) -> (level: Int, progress: Int, needed: Int) {
        var level = 1
        var remaining = xp
        while remaining >= xpForLevel(level) {
            remaining -= xpForLevel(level)
            level += 1
        }
        return (level, remaining, xpForLevel(level))
    }

    static func rank(forLevel level: Int) -> String {
        switch level {
        case ..<5: "Beginner"
        case ..<10: "Novice"
        case ..<20: "Intermediate"
        case ..<35: "Advanced"
        case ..<50: "Expert"
        default: "Pal Professor"
        }
    }

    static func rankColor(forLevel level: Int) -> Color {
        switch level {
        case ..<5: .gray
        case ..<10: .green
        case ..<20: .blue
        case ..<35: .purple
        case ..<50: .orange
        default: .red
        }
    }
}

// MARK: - Store

/// All progression writes go through here (DESIGN.md §11 ProgressionStore).
@MainActor
enum ProgressionStore {
    static func profile(_ context: ModelContext) -> PlayerProfile {
        if let existing = try? context.fetch(FetchDescriptor<PlayerProfile>()).first {
            return existing
        }
        let fresh = PlayerProfile()
        context.insert(fresh)
        return fresh
    }

    static func facetProgress(_ context: ModelContext, entityID: String, facet: String)
        -> FacetProgress {
        let descriptor = FetchDescriptor<FacetProgress>(predicate: #Predicate {
            $0.entityID == entityID && $0.facet == facet
        })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = FacetProgress(entityID: entityID, facet: facet)
        context.insert(fresh)
        return fresh
    }

    static func addCategoryXP(_ context: ModelContext, categoryID: String, amount: Int) {
        let descriptor = FetchDescriptor<CategoryXP>(predicate: #Predicate {
            $0.categoryID == categoryID
        })
        let record = (try? context.fetch(descriptor).first) ?? {
            let fresh = CategoryXP(categoryID: categoryID)
            context.insert(fresh)
            return fresh
        }()
        record.xp += amount
    }

    /// Record one answered question. Returns the XP awarded (with redemption).
    @discardableResult
    static func recordAnswer(_ context: ModelContext, data: GameData,
                             question: Question, correct: Bool,
                             difficulty: Difficulty, streak: Int) -> Int {
        let facetRecord = facetProgress(context, entityID: question.subjectID,
                                        facet: question.facet)
        var earned = 0
        if correct {
            facetRecord.correctCount += 1
            var base = Double(question.baseXP) * difficulty.xpMultiplier
            // redemption: this exact question was missed before
            let signature = question.signature
            let missDescriptor = FetchDescriptor<MissRecord>(predicate: #Predicate {
                $0.signature == signature && !$0.redeemed
            })
            if let miss = try? context.fetch(missDescriptor).first {
                base *= 2
                miss.redeemed = true
            }
            earned = Int(base) + min(2 * streak, 10)
            // NOTE: not applied to the profile here — quizzes pay out only on
            // finish (QuizView.saveSession); abandoning a quiz earns nothing.
            for category in question.categoryIDs {
                addCategoryXP(context, categoryID: category, amount: 1)
            }
        } else {
            facetRecord.missCount += 1
            context.insert(MissRecord(signature: question.signature))
        }
        return earned
    }

    /// Total correct answers about an entity (avatar unlock at 5).
    static func totalCorrect(_ context: ModelContext, entityID: String) -> Int {
        let descriptor = FetchDescriptor<FacetProgress>(predicate: #Predicate {
            $0.entityID == entityID
        })
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.correctCount }
    }
}

// MARK: - Read-model helpers for the Progression tab

struct ProgressionSnapshot {
    /// entity id -> facet -> net correct
    let facets: [String: [String: Int]]
    /// entity id -> lifetime correct answers (avatar unlocks)
    let rawCorrect: [String: Int]
    /// entity id -> lifetime misses (Weakest Pals ranking)
    let rawMisses: [String: Int]

    init(records: [FacetProgress]) {
        var map: [String: [String: Int]] = [:]
        var raw: [String: Int] = [:]
        var misses: [String: Int] = [:]
        for record in records {
            map[record.entityID, default: [:]][record.facet] = record.netCorrect
            raw[record.entityID, default: 0] += record.correctCount
            misses[record.entityID, default: 0] += record.missCount
        }
        facets = map
        rawCorrect = raw
        rawMisses = misses
    }

    func masteredFacetCount(entityID: String) -> Int {
        Progression.palFacets.filter {
            (facets[entityID]?[$0] ?? 0) >= Progression.masteryThreshold
        }.count
    }

    /// 0...1 — partial credit per facet (net/threshold, capped), averaged
    /// across facets, so bars move from the first correct answer instead of
    /// staying at 0 until a facet is fully mastered.
    func completeness(entityID: String) -> Double {
        let perFacet = Progression.palFacets.map { facet -> Double in
            let net = facets[entityID]?[facet] ?? 0
            return min(Double(net), Double(Progression.masteryThreshold))
                / Double(Progression.masteryThreshold)
        }
        return perFacet.reduce(0, +) / Double(Progression.palFacets.count)
    }

    /// 0...1 — mean completeness across entities.
    func completeness(entityIDs: [String]) -> Double {
        guard !entityIDs.isEmpty else { return 0 }
        return entityIDs.map { completeness(entityID: $0) }.reduce(0, +)
            / Double(entityIDs.count)
    }

    func totalCorrect(entityID: String) -> Int {
        rawCorrect[entityID] ?? 0
    }

    /// The `count` pals you know least: misses first, then lowest completeness,
    /// padded with never-seen pals — mixing ≥10 subjects keeps a targeted quiz
    /// from telegraphing its answers (unlike single-pal/element quizzes).
    func weakestPals(in pool: [Pal], count: Int) -> [Pal] {
        pool.sorted {
            let lhs = (completeness(entityID: $0.id), -Double(rawMisses[$0.id] ?? 0))
            let rhs = (completeness(entityID: $1.id), -Double(rawMisses[$1.id] ?? 0))
            if lhs != rhs { return lhs < rhs }
            return $0.id < $1.id
        }
        .prefix(count).shuffled()
    }
}
