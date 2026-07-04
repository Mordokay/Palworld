import SwiftUI
import SwiftData

/// A question domain the player can quiz in isolation — used by the Game
/// tab's topic chips and the Time Attack / Survival setup pickers.
struct QuizTopic: Identifiable {
    let id: String
    let label: String
    let icon: String
    let tint: Color
    /// nil = the full mixed catalog
    let templates: [any QuestionTemplate]?

    static let all: [QuizTopic] = [
        QuizTopic(id: "all", label: "Everything", icon: "sparkles", tint: .purple,
                  templates: nil),
        QuizTopic(id: "pals", label: "Pals", icon: "pawprint.fill", tint: .green,
                  templates: QuizEngine.palTemplates),
        QuizTopic(id: "items", label: "Items", icon: "bag.fill", tint: .orange,
                  templates: QuizEngine.itemTemplates),
        QuizTopic(id: "skills", label: "Skills", icon: "bolt.circle.fill", tint: .mint,
                  templates: QuizEngine.skillTemplates),
        QuizTopic(id: "buildings", label: "Buildings", icon: "house.fill", tint: .brown,
                  templates: QuizEngine.buildingTemplates),
        QuizTopic(id: "world", label: "World & Lore", icon: "globe.europe.africa.fill",
                  tint: .teal, templates: QuizEngine.worldTemplates),
    ]
}

/// Game tab: Daily Challenge up top, then the mode catalog (DESIGN.md §5).
struct GameHomeView: View {
    let data: GameData
    @Environment(\.modelContext) private var modelContext
    @Query private var activeQuizzes: [ActiveQuiz]
    @Query private var sessions: [QuizSession]
    @Query private var facetRecords: [FacetProgress]
    @Query private var profiles: [PlayerProfile]
    @Query private var missRecords: [MissRecord]

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

                    let due = Progression.dueReviewSignatures(missRecords)
                    if !due.isEmpty {
                        smartReviewCard(due)
                    }

                    NavigationLink {
                        QuizSetupView(data: data)
                    } label: {
                        ModeCard(title: "Quick Quiz", symbol: "bolt.fill",
                                 subtitle: "Pals, items, skills — your pick", locked: false)
                    }
                    .buttonStyle(.plain)

                    topicChips

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        modeLink("Time Attack", "timer", "Beat the clock") {
                            TimeAttackSetupView(data: data)
                        }
                        modeLink("Survival", "heart.fill", "3 lives, rising heat") {
                            SurvivalSetupView(data: data)
                        }
                        modeLink("Who's that Pal?", "moon.stars.fill", "Up to 100 rounds · 2 styles") {
                            WhosThatPalSetupView(data: data)
                        }
                        modeLink("Spin the Wheel", "dice.fill",
                                 "Random topic, \(SpinWheelView.questionRange.lowerBound)–\(SpinWheelView.questionRange.upperBound) questions") {
                            SpinWheelView(data: data)
                        }
                        modeLink("Weakest Pals", "target", "Drill your 10 worst") {
                            QuizView(data: data,
                                     questions: QuizEngine.makeSession(
                                         data: data, count: 10,
                                         difficulty: preferredDifficulty,
                                         subjectIDs: ProgressionSnapshot(records: facetRecords)
                                             .weakestPals(in: data.quizPals, count: 10)
                                             .map(\.id)),
                                     difficulty: preferredDifficulty,
                                     categoryLabel: "Weakest Pals",
                                     sessionMode: "weakest")
                        }
                        modeLink("Placement Test", "dial.medium.fill",
                                 "Sets difficulty: \(preferredDifficulty.label)") {
                            PlacementTestView(data: data)
                        }
                        modeLink("Teacher", "graduationcap.fill", "Study first, then prove it") {
                            TeacherSetupView(data: data)
                        }
                        modeLink("Higher / Lower", "arrow.up.arrow.down",
                                 "Endless stat chain") {
                            HigherLowerSetupView(data: data)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Palworld Trainer")
        }
    }

    /// One-tap topic quizzes: "just ask me about buildings" without a setup
    /// screen — 10 questions at the preferred difficulty.
    private var topicChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUIZ BY TOPIC")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            FlowLayout(spacing: 8) {
                ForEach(QuizTopic.all.dropFirst()) { topic in
                    NavigationLink {
                        QuizView(data: data,
                                 questions: QuizEngine.makeSession(
                                     data: data, count: 10,
                                     difficulty: preferredDifficulty,
                                     templates: topic.templates),
                                 difficulty: preferredDifficulty,
                                 categoryLabel: topic.label,
                                 sessionMode: "quick")
                    } label: {
                        Label(topic.label, systemImage: topic.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(topic.tint.opacity(0.14), in: Capsule())
                            .overlay(Capsule().stroke(topic.tint.opacity(0.35), lineWidth: 1))
                            .foregroundStyle(topic.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
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

    // MARK: - Smart Review (DESIGN.md §5: missed questions come back due)

    private func smartReviewCard(_ due: [String]) -> some View {
        let batch = Array(due.prefix(20))
        return NavigationLink {
            QuizView(data: data,
                     questions: QuizEngine.regenerate(data: data, signatures: batch,
                                                      difficulty: preferredDifficulty),
                     difficulty: preferredDifficulty,
                     categoryLabel: "Smart Review",
                     sessionMode: "review")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.largeTitle)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Review")
                        .font(.headline)
                    Text("\(due.count) missed question\(due.count == 1 ? "" : "s") due — redeem for 2× XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(.purple.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Daily Challenge (DESIGN.md §5: date-seeded, one scored try/day)

    private var todaysDaily: QuizSession? {
        sessions.first { $0.mode == "daily" && $0.dayKey == Progression.todayKey }
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
                             seed: Self.dailySeed(for: Progression.todayKey)),
                         difficulty: .medium,
                         categoryLabel: "Daily Challenge",
                         sessionMode: "daily",
                         dailyKey: Progression.todayKey)
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
                let streak = Progression.dailyStreak(sessions: sessions)
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
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
    @State private var topic = "All"

    private static let topics: [String: [any QuestionTemplate]?] = [
        "All": nil,   // makeSession default = the full mixed catalog
        "Pals": QuizEngine.palTemplates,
        "Items": QuizEngine.itemTemplates,
        "Skills": QuizEngine.skillTemplates,
        "World": QuizEngine.worldTemplates,
        "Buildings": QuizEngine.buildingTemplates,
    ]

    var body: some View {
        Form {
            Section("Topic") {
                Picker("Topic", selection: $topic) {
                    ForEach(["All", "Pals", "Items", "Skills", "World", "Buildings"],
                            id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
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
                                 data: data, count: count, difficulty: difficulty,
                                 templates: Self.topics[topic] ?? nil),
                             difficulty: difficulty,
                             categoryLabel: topic)
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

/// "Who's that Pal?" comes in two flavors: the classic pitch-black silhouette
/// (cutout artwork only) and the full drawing (every pal with an image —
/// opaque screenshots welcome here).
struct WhosThatPalSetupView: View {
    let data: GameData
    @Query private var profiles: [PlayerProfile]
    @State private var rounds = 20

    private var preferredDifficulty: Difficulty {
        Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "") ?? .medium
    }

    var body: some View {
        Form {
            Section("Rounds") {
                Picker("Rounds", selection: $rounds) {
                    ForEach([20, 40, 60, 80, 100], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                NavigationLink {
                    quiz(silhouette: true)
                } label: {
                    styleRow("Silhouettes", icon: "moon.stars.fill", tint: .indigo,
                             note: "The classic — name the pitch-black shape")
                }
                NavigationLink {
                    quiz(silhouette: false)
                } label: {
                    styleRow("Full artwork", icon: "photo.fill", tint: .blue,
                             note: "The real drawing — every pal can appear")
                }
            }
        }
        .navigationTitle("Who's that Pal?")
    }

    private func styleRow(_ title: String, icon: String, tint: Color,
                          note: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func quiz(silhouette: Bool) -> some View {
        QuizView(data: data,
                 questions: QuizEngine.makeSession(
                     data: data, count: rounds, difficulty: preferredDifficulty,
                     templates: [silhouette ? SilhouetteTemplate()
                                            : PictureToNameTemplate()]),
                 difficulty: preferredDifficulty,
                 categoryLabel: silhouette ? "Who's that Pal?" : "Who's that Pal? · Artwork",
                 sessionMode: "whosthatpal")
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
