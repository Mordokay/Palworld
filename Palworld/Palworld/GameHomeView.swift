import SwiftUI

/// Game tab: mode grid. Only Quick Quiz is playable in M2; the rest preview
/// the roadmap so the shape of the app is visible from day one.
struct GameHomeView: View {
    let data: GameData

    private static let comingSoon: [(String, String)] = [
        ("Time Attack", "timer"),
        ("Survival", "heart.slash"),
        ("Higher / Lower", "arrow.up.arrow.down"),
        ("Daily Challenge", "calendar.badge.clock"),
        ("Spin the Wheel", "dice.fill"),
        ("Teacher", "graduationcap.fill"),
        ("Who's that Pal?", "questionmark.circle.fill"),
        ("Smart Review", "brain.head.profile"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        QuizSetupView(data: data)
                    } label: {
                        ModeCard(title: "Quick Quiz", symbol: "bolt.fill",
                                 subtitle: "10 questions about pals", locked: false)
                    }
                    .buttonStyle(.plain)

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
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .opacity(locked ? 0.55 : 1)
    }
}

/// Difficulty + length picker before starting a quiz.
struct QuizSetupView: View {
    let data: GameData
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
    }
}
