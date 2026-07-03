import SwiftUI

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
            do { data = try GameData.load() } catch { loadError = String(describing: error) }
        }
    }
}

struct MainTabView: View {
    let data: GameData

    var body: some View {
        TabView {
            Tab("Game", systemImage: "gamecontroller.fill") {
                GameHomeView(data: data)
            }
            Tab("Progression", systemImage: "chart.bar.fill") {
                PlaceholderTab(title: "Progression", symbol: "chart.bar.fill",
                               note: "Knowledge bars per category and pal — lands in M4.")
            }
            Tab("Library", systemImage: "books.vertical.fill") {
                LibraryView(data: data)
            }
            Tab("Achievements", systemImage: "trophy.fill") {
                PlaceholderTab(title: "Achievements", symbol: "trophy.fill",
                               note: "Unlockable badges — lands in M6.")
            }
            Tab("Profile", systemImage: "person.crop.circle") {
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

struct ProfileView: View {
    let data: GameData

    var body: some View {
        NavigationStack {
            List {
                Section("Bundled game data") {
                    LabeledContent("Pals", value: "\(data.pals.count)")
                    LabeledContent("Items", value: "\(data.items.count)")
                    LabeledContent("Weapons", value: "\(data.weapons.count)")
                    LabeledContent("Skills", value: "\(data.skills.count)")
                    LabeledContent("Locations", value: "\(data.locations.count)")
                    LabeledContent("Library articles", value: "\(data.articles.count)")
                }
                Section {
                    Text("Profile, XP and stats arrive in M4.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    AppRoot()
}
