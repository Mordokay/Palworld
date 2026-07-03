import SwiftUI
import SwiftData

/// Game tab: Daily Challenge up top, then the mode catalog (DESIGN.md §5).
struct GameHomeView: View {
    let data: GameData
    @Environment(\.modelContext) private var modelContext
    @Query private var activeQuizzes: [ActiveQuiz]
    @Query private var sessions: [QuizSession]
    @Query private var facetRecords: [FacetProgress]
    @Query private var profiles: [PlayerProfile]

    private static let comingSoon: [(String, String)] = [
        ("Higher / Lower", "arrow.up.arrow.down"),
        ("Teacher", "graduationcap.fill"),
        ("Smart Review", "brain.head.profile"),
    ]

    private var preferredDifficulty: Difficulty {
        Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "") ?? .medium
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let active = activeQuizzes.first, !active.questions.isEmpty {
                        resumeCard(active)
                    }

                    dailyCard

                    NavigationLink {
                        QuizSetupView(data: data)
                    } label: {
                        ModeCard(title: "Quick Quiz", symbol: "bolt.fill",
                                 subtitle: "10 questions about pals", locked: false)
                    }
                    .buttonStyle(.plain)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        modeLink("Time Attack", "timer", "Beat the clock") {
                            TimeAttackSetupView(data: data)
                        }
                        modeLink("Survival", "heart.fill", "3 lives, rising heat") {
                            SurvivalSetupView(data: data)
                        }
                        modeLink("Who's that Pal?", "moon.stars.fill", "20 silhouettes") {
                            QuizView(data: data,
                                     questions: QuizEngine.makeSession(
                                         data: data, count: 20,
                                         difficulty: preferredDifficulty,
                                         templates: [SilhouetteTemplate()]),
                                     difficulty: preferredDifficulty,
                                     categoryLabel: "Who's that Pal?",
                                     sessionMode: "whosthatpal")
                        }
                        modeLink("Spin the Wheel", "dice.fill", "Random topic, 5 questions") {
                            SpinWheelView(data: data)
                        }
                        modeLink("Weakest Pals", "target", "Drill your 10 worst") {
                            QuizView(data: data,
                                     questions: QuizEngine.makeSession(
                                         data: data, count: 10,
                                         difficulty: preferredDifficulty,
                                         subjects: ProgressionSnapshot(records: facetRecords)
                                             .weakestPals(in: data.quizPals, count: 10)),
                                     difficulty: preferredDifficulty,
                                     categoryLabel: "Weakest Pals",
                                     sessionMode: "weakest")
                        }
                        modeLink("Placement Test", "dial.medium.fill",
                                 "Sets difficulty: \(preferredDifficulty.label)") {
                            PlacementTestView(data: data)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(Self.comingSoon, id: \.0) { mode in
                            ModeCard(title: mode.0, symbol: mode.1,
                                     subtitle: "Coming soon", locked: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Palworld Trainer")
        }
    }

    private func modeLink<D: View>(_ title: String, _ symbol: String, _ subtitle: String,
                                   @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            ModeCard(title: title, symbol: symbol, subtitle: subtitle, locked: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Daily Challenge (DESIGN.md §5: date-seeded, one scored try/day)

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var todayKey: String { Self.dayFormatter.string(from: .now) }

    private var todaysDaily: QuizSession? {
        sessions.first { $0.mode == "daily" && $0.dayKey == todayKey }
    }

    /// Consecutive days played, counting back from today (or yesterday, so an
    /// unplayed today doesn't read as a broken streak).
    private var dailyStreak: Int {
        let played = Set(sessions.filter { $0.mode == "daily" }.map(\.dayKey))
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: .now)
        if !played.contains(Self.dayFormatter.string(from: day)) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while played.contains(Self.dayFormatter.string(from: day)) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    /// Stable FNV-1a hash of the day key — Swift's `hashValue` is randomized
    /// per launch and would change the "same quiz all day" seed.
    private static func dailySeed(for key: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    @ViewBuilder
    private var dailyCard: some View {
        let played = todaysDaily
        NavigationLink {
            if let played {
                SessionDetailView(data: data, session: played)
            } else {
                QuizView(data: data,
                         questions: QuizEngine.makeSession(
                             data: data, count: 10, difficulty: .medium,
                             seed: Self.dailySeed(for: todayKey)),
                         difficulty: .medium,
                         categoryLabel: "Daily Challenge",
                         sessionMode: "daily",
                         dailyKey: todayKey)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: played == nil ? "calendar.badge.clock" : "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(played == nil ? .yellow : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Challenge")
                        .font(.headline)
                    Text(played.map { "Done today — \($0.bestScore)/\($0.signatures.count)" }
                         ?? "10 questions · same quiz for everyone all day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if dailyStreak > 0 {
                    Label("\(dailyStreak)", systemImage: "flame.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(.yellow.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The one in-progress quiz — survives app restarts; answers auto-save.
    private func resumeCard(_ active: ActiveQuiz) -> some View {
        NavigationLink {
            QuizView(data: data,
                     questions: active.questions,
                     difficulty: Difficulty(rawValue: active.difficulty) ?? .medium,
                     categoryLabel: active.categoryLabel,
                     replayOf: sessions.first { $0.uuid == active.replaySessionUUID },
                     resume: active,
                     sessionMode: active.mode,
                     dailyKey: active.dayKey,
                     onFinish: active.mode == "placement"
                         ? { Placement.grade($0, context: modelContext) } : nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue quiz")
                        .font(.headline)
                    Text("\(active.categoryLabel) · question \(active.pickedIndexes.count + 1) of \(active.questions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    modelContext.delete(active)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ModeCard: View {
    let title: String
    let symbol: String
    let subtitle: String
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: locked ? "lock.fill" : symbol)
                .font(.title2)
                .foregroundStyle(locked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .opacity(locked ? 0.55 : 1)
    }
}

/// Difficulty + length picker before starting a quiz. Defaults to the
/// difficulty the Placement Test recommended.
struct QuizSetupView: View {
    let data: GameData
    @Query private var profiles: [PlayerProfile]
    @State private var difficulty: Difficulty = .medium
    @State private var count = 10

    var body: some View {
        Form {
            Section("Difficulty") {
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(Difficulty.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Questions") {
                Picker("Questions", selection: $count) {
                    ForEach([5, 10, 20], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                NavigationLink("Start Quiz") {
                    QuizView(data: data,
                             questions: QuizEngine.makeSession(
                                 data: data, count: count, difficulty: difficulty),
                             difficulty: difficulty)
                }
                .font(.headline)
            }
        }
        .navigationTitle("Quick Quiz")
        .onAppear {
            if let preferred = Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "") {
                difficulty = preferred
            }
        }
    }
}

/// 12 questions sweeping easy → medium → hard; the tier you hold up in sets
/// your recommended difficulty (DESIGN.md §5). Retakable anytime.
struct PlacementTestView: View {
    let data: GameData
    @Environment(\.modelContext) private var modelContext
    @State private var questions: [Question]

    init(data: GameData) {
        self.data = data
        let tiers = Difficulty.allCases.flatMap {
            QuizEngine.makeSession(data: data, count: Placement.tierSize, difficulty: $0)
        }
        _questions = State(initialValue: tiers)
    }

    var body: some View {
        QuizView(data: data, questions: questions, difficulty: .medium,
                 categoryLabel: "Placement Test", sessionMode: "placement",
                 onFinish: { Placement.grade($0, context: modelContext) })
    }
}

/// Shared so a placement test resumed from the Continue card still grades.
@MainActor
enum Placement {
    static let tierSize = 4

    /// ≥3 of 4 right in a tier means you belong at least there.
    static func grade(_ answered: [AnsweredQuestion], context: ModelContext) {
        func tierScore(_ tier: Int) -> Int {
            answered.dropFirst(tier * tierSize).prefix(tierSize)
                .filter(\.wasCorrect).count
        }
        let recommended: Difficulty = tierScore(2) >= 3 ? .hard
            : tierScore(1) >= 3 ? .medium : .easy
        ProgressionStore.profile(context).preferredDifficulty = recommended.rawValue
    }
}
