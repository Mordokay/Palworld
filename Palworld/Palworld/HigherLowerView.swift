import SwiftUI
import SwiftData

/// One comparable thing in a Higher/Lower chain.
struct HLEntry: Identifiable {
    let id: String
    let name: String
    let imageFile: String
    let imageKind: GameData.ImageKind
    let value: Double
    let display: String
}

/// A comparison category: "more base HP", "pricier", "heavier"...
struct HLCategory: Identifiable {
    let id: String
    let label: String
    let question: String      // "has more base HP"
    let symbol: String
    let color: Color
    let entries: (GameData) -> [HLEntry]

    static let all: [HLCategory] = [
        HLCategory(id: "hp", label: "Base HP", question: "has more base HP",
                   symbol: "heart.fill", color: .green) { data in
            data.quizPalsWithImage.compactMap { pal in
                (pal.stats?.hp).map {
                    HLEntry(id: pal.id, name: pal.name, imageFile: pal.image,
                            imageKind: .pals, value: Double($0), display: "\($0) HP")
                }
            }
        },
        HLCategory(id: "attack", label: "Base Attack", question: "has more base Attack",
                   symbol: "flame.fill", color: .red) { data in
            data.quizPalsWithImage.compactMap { pal in
                (pal.stats?.attack).map {
                    HLEntry(id: pal.id, name: pal.name, imageFile: pal.image,
                            imageKind: .pals, value: Double($0), display: "\($0) ATK")
                }
            }
        },
        HLCategory(id: "defense", label: "Base Defense", question: "has more base Defense",
                   symbol: "shield.fill", color: .blue) { data in
            data.quizPalsWithImage.compactMap { pal in
                (pal.stats?.defense).map {
                    HLEntry(id: pal.id, name: pal.name, imageFile: pal.image,
                            imageKind: .pals, value: Double($0), display: "\($0) DEF")
                }
            }
        },
        HLCategory(id: "food", label: "Appetite", question: "eats more food",
                   symbol: "fork.knife", color: .brown) { data in
            data.quizPalsWithImage.compactMap { pal in
                pal.foodAmount.map {
                    HLEntry(id: pal.id, name: pal.name, imageFile: pal.image,
                            imageKind: .pals, value: Double($0), display: "Food \($0)/10")
                }
            }
        },
        HLCategory(id: "gold", label: "Gold Price", question: "costs more gold",
                   symbol: "dollarsign.circle.fill", color: .orange) { data in
            (data.items + data.weapons).compactMap { item in
                (item.goldBuy).flatMap { $0 > 0 ? $0 : nil }.map {
                    HLEntry(id: item.id, name: item.name, imageFile: item.image,
                            imageKind: .items, value: Double($0), display: "\($0) gold")
                }
            }
        },
        HLCategory(id: "weight", label: "Weight", question: "weighs more",
                   symbol: "scalemass.fill", color: .gray) { data in
            (data.items + data.weapons).compactMap { item in
                (item.weight).flatMap { $0 > 0 ? $0 : nil }.map {
                    HLEntry(id: item.id, name: item.name, imageFile: item.image,
                            imageKind: .items, value: $0,
                            display: String(format: "%.1f weight", $0))
                }
            }
        },
        HLCategory(id: "tech", label: "Tech Level", question: "unlocks at a higher tech level",
                   symbol: "dial.medium.fill", color: .cyan) { data in
            (data.items + data.weapons).compactMap { item in
                (item.techTier).flatMap { $0 > 0 ? $0 : nil }.map {
                    HLEntry(id: item.id, name: item.name, imageFile: item.image,
                            imageKind: .items, value: Double($0), display: "Tech \($0)")
                }
            }
        },
        HLCategory(id: "damage", label: "Weapon Damage", question: "deals more damage",
                   symbol: "burst.fill", color: .pink) { data in
            data.weapons.compactMap { weapon in
                (weapon.damage).flatMap { $0 > 0 ? $0 : nil }.map {
                    HLEntry(id: weapon.id, name: weapon.name, imageFile: weapon.image,
                            imageKind: .weapons, value: Double($0), display: "\($0) DMG")
                }
            }
        },
        HLCategory(id: "nutrition", label: "Nutrition", question: "is more nutritious",
                   symbol: "carrot.fill", color: .mint) { data in
            data.items.compactMap { item in
                (item.nutrition).flatMap { $0 > 0 ? $0 : nil }.map {
                    HLEntry(id: item.id, name: item.name, imageFile: item.image,
                            imageKind: .items, value: Double($0),
                            display: "\($0) nutrition")
                }
            }
        },
        HLCategory(id: "power", label: "Skill Power", question: "has more power",
                   symbol: "sparkles", color: .purple) { data in
            data.skills.compactMap { skill in
                (skill.power).flatMap { $0 > 0 ? $0 : nil }.map {
                    HLEntry(id: skill.id, name: skill.name,
                            imageFile: skill.image ?? Theme.elementIconFile(skill.element.capitalized),
                            imageKind: .ui, value: Double($0), display: "\($0) power")
                }
            }
        },
    ]
}

struct HigherLowerSetupView: View {
    let data: GameData

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    HigherLowerPlayView(data: data,
                                        category: HLCategory.all.randomElement()!)
                } label: {
                    Label("Surprise me", systemImage: "dice.fill")
                        .font(.headline)
                }
            }
            Section {
                ForEach(HLCategory.all) { category in
                    NavigationLink {
                        HigherLowerPlayView(data: data, category: category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .foregroundStyle(category.color)
                                .frame(width: 28)
                            Text(category.label)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            } header: {
                Text("Pick a stat")
            } footer: {
                Text("Endless chain — one wrong guess ends the run. 10 XP per correct answer.")
            }
        }
        .navigationTitle("Higher / Lower")
    }
}

struct HigherLowerPlayView: View {
    let data: GameData
    let category: HLCategory

    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [QuizSession]
    @State private var pool: [HLEntry] = []
    @State private var current: HLEntry?
    @State private var next: HLEntry?
    @State private var revealed = false
    @State private var lastGuessCorrect = false
    @State private var streak = 0
    @State private var gameOver = false
    @State private var saved = false

    private var allTimeBest: Int {
        sessions.filter { $0.mode == "higherlower" && $0.categoryLabel.contains(category.label) }
            .map(\.bestScore).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 14) {
            hud
            if let current, let next {
                entryCard(current, revealed: true)
                Label("Which \(category.question)?", systemImage: category.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(category.color)
                entryCard(next, revealed: revealed)
                buttons
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(category.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(streak > 0 && !gameOver)
        .onAppear(perform: start)
        .overlay {
            if gameOver {
                gameOverCard
            }
        }
    }

    private var hud: some View {
        HStack {
            Label("\(streak)", systemImage: "flame.fill")
                .font(.title3.weight(.black))
                .foregroundStyle(.orange)
            Spacer()
            Label("Best \(max(allTimeBest, streak))", systemImage: "trophy.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.yellow)
        }
    }

    private func entryCard(_ entry: HLEntry, revealed: Bool) -> some View {
        HStack(spacing: 14) {
            WikiImage(file: entry.imageFile, kind: entry.imageKind)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.headline)
                Text(revealed ? entry.display : "???")
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(revealed ? category.color : .secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(category.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(category.color.opacity(0.3), lineWidth: 1))
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            guessButton(higher: false, label: "Lower", symbol: "arrow.down", tint: .red)
            guessButton(higher: true, label: "Higher", symbol: "arrow.up", tint: .green)
        }
    }

    private func guessButton(higher: Bool, label: String, symbol: String,
                             tint: Color) -> some View {
        Text("\(Image(systemName: symbol)) \(label)")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint.opacity(revealed ? 0.06 : 0.15),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(revealed ? 0.15 : 0.5), lineWidth: 2))
            .foregroundStyle(revealed ? .secondary : .primary)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { guess(higher: higher) }
    }

    private var gameOverCard: some View {
        VStack(spacing: 14) {
            Image(systemName: streak > allTimeBest ? "trophy.fill" : "flag.checkered")
                .font(.system(size: 44))
                .foregroundStyle(streak > allTimeBest ? .yellow : .secondary)
            Text(streak > allTimeBest ? "New best!" : "Run over")
                .font(.title2.bold())
            Text("\(streak) in a row · +\(streak * 10) XP")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                restart()
            } label: {
                Label("Go again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(category.color)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(30)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Flow

    private func start() {
        guard pool.isEmpty else { return }
        pool = category.entries(data).shuffled()
        guard pool.count >= 4 else { return }
        current = pool.removeFirst()
        next = draw()
    }

    /// Next contender: a different value, so higher/lower is never a tie.
    private func draw() -> HLEntry? {
        guard let current else { return nil }
        if let index = pool.firstIndex(where: { $0.value != current.value }) {
            return pool.remove(at: index)
        }
        // pool exhausted — recycle everything but the current card
        pool = category.entries(data).shuffled().filter { $0.id != current.id }
        guard let index = pool.firstIndex(where: { $0.value != current.value })
        else { return nil }
        return pool.remove(at: index)
    }

    private func guess(higher: Bool) {
        guard !revealed, !gameOver, let currentEntry = current, let nextEntry = next
        else { return }
        let correct = (nextEntry.value > currentEntry.value) == higher
        Haptics.answer(correct: correct)
        lastGuessCorrect = correct
        withAnimation(.snappy(duration: 0.3)) {
            revealed = true
        }
        Task {
            try? await Task.sleep(for: .seconds(correct ? 0.9 : 1.4))
            if correct {
                streak += 1
                withAnimation(.snappy(duration: 0.3)) {
                    current = nextEntry
                    next = draw()
                    revealed = false
                }
            } else {
                finish()
            }
        }
    }

    private func finish() {
        guard !saved else { return }
        saved = true
        let earned = streak * 10
        ProgressionStore.profile(modelContext).xp += earned
        let session = QuizSession()
        session.mode = "higherlower"
        session.categoryLabel = "Higher / Lower · \(category.label)"
        session.bestScore = streak
        session.xpEarned = earned
        modelContext.insert(session)
        withAnimation(.snappy(duration: 0.35)) {
            gameOver = true
        }
    }

    private func restart() {
        pool = []
        current = nil
        next = nil
        revealed = false
        streak = 0
        saved = false
        withAnimation(.snappy(duration: 0.25)) {
            gameOver = false
        }
        start()
    }
}
