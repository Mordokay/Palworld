import SwiftUI
import SwiftData

/// Teacher mode (DESIGN.md §5): pick a topic, study its Library pages at
/// leisure, then prove it with a quiz restricted to that topic.
struct TeacherSetupView: View {
    let data: GameData
    @State private var count = 20

    var body: some View {
        Form {
            Section("Questions") {
                Picker("Questions", selection: $count) {
                    ForEach([20, 40, 60, 80, 100], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Pick a topic to study") {
                ForEach(Theme.allElements, id: \.self) { element in
                    let members = pals(for: element)
                    if !members.isEmpty {
                        NavigationLink {
                            TeacherStudyView(data: data, topic: element,
                                             members: members, count: count)
                        } label: {
                            HStack(spacing: 10) {
                                WikiImage(file: Theme.elementIconFile(element), kind: .ui)
                                    .frame(width: 24, height: 24)
                                Text("\(element) Pals")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.elementColor(element))
                                Spacer()
                                Text("\(members.count)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Teacher")
    }

    private func pals(for element: String) -> [Pal] {
        data.quizPals
            .filter { $0.elements.contains(element) }
            .sorted { ($0.number.isEmpty ? "999" : $0.number) < ($1.number.isEmpty ? "999" : $1.number) }
    }
}

/// Study phase: the topic's pals as browsable Library pages, then "I'm ready".
struct TeacherStudyView: View {
    let data: GameData
    let topic: String
    let members: [Pal]
    let count: Int
    @Query private var profiles: [PlayerProfile]
    @State private var studyPalID: String?

    private var preferredDifficulty: Difficulty {
        Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "") ?? .medium
    }

    var body: some View {
        List {
            Section {
                Text("Read up on your \(topic) pals — tap any of them to open their page. Start the quiz whenever you feel ready.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("\(members.count) pals to study") {
                ForEach(members) { pal in
                    Button {
                        studyPalID = pal.id
                    } label: {
                        HStack(spacing: 10) {
                            WikiImage(file: pal.image, kind: .pals)
                                .frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pal.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !pal.number.isEmpty {
                                    Text("#\(pal.number)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "book.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(topic) study hall")
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                QuizView(data: data,
                         questions: QuizEngine.makeSession(
                             data: data, count: count, difficulty: preferredDifficulty,
                             subjects: members,
                             // element questions would answer themselves when
                             // every subject shares the studied element
                             templates: QuizEngine.palTemplates.filter { $0.facet != "elements" }),
                         difficulty: preferredDifficulty,
                         categoryLabel: "Teacher · \(topic)",
                         sessionMode: "teacher")
            } label: {
                Label("I'm ready — \(count) questions", systemImage: "graduationcap.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.elementColor(topic))
            .padding()
            .background(.bar)
        }
        .sheet(item: $studyPalID) { id in
            ArticleSheetView(data: data, articleID: id)
        }
    }
}
