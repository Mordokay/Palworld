import SwiftUI
import SwiftData

/// Loads the bundled game data once, then shows the 5-tab shell (DESIGN.md §1).
struct AppRoot: View {
    @State private var data: GameData?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let data {
                // debug hook: `simctl launch ... -screenshot-quiz` jumps straight
                // into a seeded quiz so the screen can be verified without taps
                if CommandLine.arguments.contains("-screenshot-quiz") {
                    NavigationStack {
                        QuizView(data: data,
                                 questions: QuizEngine.makeSession(
                                     data: data, count: 5, difficulty: .medium, seed: 42),
                                 difficulty: .medium)
                    }
                } else if CommandLine.arguments.contains("-screenshot-silhouette") {
                    NavigationStack {
                        QuizView(data: data,
                                 questions: QuizEngine.makeSession(
                                     data: data, count: 5, difficulty: .medium, seed: 42,
                                     templates: [SilhouetteTemplate()]),
                                 difficulty: .medium, categoryLabel: "Who's that Pal?",
                                 sessionMode: "whosthatpal")
                    }
                } else if CommandLine.arguments.contains("-screenshot-wheel") {
                    NavigationStack { SpinWheelView(data: data) }
                } else if CommandLine.arguments.contains("-screenshot-timeattack") {
                    NavigationStack {
                        ArcadeQuizView(data: data, mode: .timeAttack(seconds: 60),
                                       difficulty: .medium)
                    }
                } else if CommandLine.arguments.contains("-screenshot-survival") {
                    NavigationStack {
                        ArcadeQuizView(data: data, mode: .survival, difficulty: .easy)
                    }
                } else if let idx = CommandLine.arguments.firstIndex(of: "-screenshot-page"),
                          CommandLine.arguments.indices.contains(idx + 1) {
                    let trail = CommandLine.arguments.firstIndex(of: "-trail")
                        .flatMap { i -> [String]? in
                            CommandLine.arguments.indices.contains(i + 1)
                                ? CommandLine.arguments[i + 1].components(separatedBy: ",") : nil
                        } ?? []
                    ArticleSheetView(data: data, articleID: CommandLine.arguments[idx + 1],
                                     initialPath: trail)
                } else {
                    MainTabView(data: data)
                }
            } else if let loadError {
                ContentUnavailableView("Data failed to load",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView("Loading Paldeck…")
            }
        }
        .fontDesign(.rounded)
        .task {
            do {
                let loaded = try GameData.load()
                data = loaded
                if CommandLine.arguments.contains("-seed-progress") {
                    seedProgress(loaded)
                }
            } catch { loadError = String(describing: error) }
        }
    }

    @Environment(\.modelContext) private var modelContext

    /// Debug: simulate played quizzes so Progression/Profile can be verified.
    private func seedProgress(_ data: GameData) {
        let water = data.quizPals.filter { $0.elements.contains("Water") }.prefix(12)
        let engine = SeededRNG(seed: 7)
        var signatures: [String] = []
        var outcomes: [Bool] = []
        for (i, pal) in water.enumerated() {
            for template in QuizEngine.palTemplates.prefix(3) {
                guard let q = template.generate(data: data, difficulty: .medium,
                                                rng: engine, subjectID: pal.id) else { continue }
                let correct = (i + signatures.count) % 4 != 0
                for _ in 0..<(correct ? 3 : 1) {
                    ProgressionStore.recordAnswer(modelContext, data: data, question: q,
                                                  correct: correct, difficulty: .medium,
                                                  streak: 1)
                }
                if signatures.count < 10 {
                    signatures.append(q.signature)
                    outcomes.append(correct)
                }
            }
        }
        // backdate the misses so the Smart Review card has something due
        for record in (try? modelContext.fetch(FetchDescriptor<MissRecord>())) ?? [] {
            record.missedAt = Date().addingTimeInterval(-2 * 86_400)
        }
        let session = QuizSession()
        session.categoryLabel = "Water Pals"
        session.signatures = signatures
        session.lastCorrect = outcomes
        session.everCorrect = outcomes
        session.bestScore = outcomes.filter { $0 }.count
        session.xpEarned = 230
        modelContext.insert(session)
    }
}

struct MainTabView: View {
    let data: GameData
    @State private var selection: String

    init(data: GameData) {
        self.data = data
        let requested = CommandLine.arguments.firstIndex(of: "-tab").flatMap { i in
            CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : nil
        }
        _selection = State(initialValue: requested ?? "game")
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Game", systemImage: "gamecontroller.fill", value: "game") {
                GameHomeView(data: data)
            }
            Tab("Progression", systemImage: "chart.bar.fill", value: "progression") {
                ProgressionView(data: data)
            }
            Tab("Library", systemImage: "books.vertical.fill", value: "library") {
                LibraryView(data: data)
            }
            Tab("Achievements", systemImage: "trophy.fill", value: "awards") {
                AchievementsView(data: data)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: "profile") {
                ProfileView(data: data)
            }
        }
    }
}

struct PlaceholderTab: View {
    let title: String
    let symbol: String
    let note: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: symbol, description: Text(note))
                .navigationTitle(title)
        }
    }
}

#Preview {
    AppRoot()
}
