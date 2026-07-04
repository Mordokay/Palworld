import SwiftUI
import SwiftData

/// One page in a Teacher study list (a pal, item, skill or guide article).
struct StudyEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
    let kind: GameData.ImageKind
}

/// A studyable topic: its Library pages plus the quiz that tests them.
struct TeacherTopic: Identifiable {
    let id: String
    let label: String
    let icon: String       // SF symbol (element topics use the wiki icon)
    let elementIcon: String?
    let tint: Color
    let entries: (GameData) -> [StudyEntry]
    let templates: [any QuestionTemplate]
    /// Scope quiz subjects to the studied pages (nil = any subject).
    let scopesSubjects: Bool
}

/// Teacher mode (DESIGN.md §5): pick a topic, study its Library pages at
/// leisure, then prove it with a quiz restricted to that topic — now for
/// every question domain, not just pals.
struct TeacherSetupView: View {
    let data: GameData
    @State private var count = 20

    private static func elementTopic(_ element: String) -> TeacherTopic {
        TeacherTopic(
            id: "element-\(element.lowercased())", label: "\(element) Pals",
            icon: "pawprint.fill", elementIcon: Theme.elementIconFile(element),
            tint: Theme.elementColor(element),
            entries: { data in
                data.quizPals
                    .filter { $0.elements.contains(element) }
                    .sorted { ($0.number.isEmpty ? "999" : $0.number) < ($1.number.isEmpty ? "999" : $1.number) }
                    .map { StudyEntry(id: $0.id, title: $0.name,
                                      subtitle: $0.number.isEmpty ? nil : "#\($0.number)",
                                      icon: $0.image, kind: .pals) }
            },
            // element questions would answer themselves when every subject
            // shares the studied element
            templates: QuizEngine.palTemplates.filter { $0.facet != "elements" },
            scopesSubjects: true)
    }

    static let extraTopics: [TeacherTopic] = [
        TeacherTopic(
            id: "weapons-armor", label: "Weapons & Armor", icon: "shield.lefthalf.filled",
            elementIcon: nil, tint: .red,
            entries: { data in
                (data.weapons + data.items.filter { ["Armor", "Accessory"].contains($0.type) })
                    .sorted { $0.name < $1.name }
                    .map { StudyEntry(id: $0.id, title: $0.name, subtitle: $0.type,
                                      icon: $0.image, kind: .items) }
            },
            templates: QuizEngine.itemTemplates, scopesSubjects: true),
        TeacherTopic(
            id: "food-cooking", label: "Food & Cooking", icon: "fork.knife",
            elementIcon: nil, tint: .orange,
            entries: { data in
                data.items.filter { ($0.nutrition ?? 0) > 0 }
                    .sorted { $0.name < $1.name }
                    .map { StudyEntry(id: $0.id, title: $0.name,
                                      subtitle: ($0.nutrition).map { "Nutrition \($0)" },
                                      icon: $0.image, kind: .items) }
            },
            templates: QuizEngine.itemTemplates + [NutritionPickTemplate()],
            scopesSubjects: true),
        TeacherTopic(
            id: "skills", label: "Active Skills", icon: "bolt.circle.fill",
            elementIcon: nil, tint: .purple,
            entries: { data in
                data.skills.filter { !Progression.facets(for: $0).isEmpty }
                    .sorted { $0.name < $1.name }
                    .map { StudyEntry(id: $0.id, title: $0.name,
                                      subtitle: $0.element.isEmpty ? nil : $0.element.capitalized,
                                      icon: $0.image, kind: .skills) }
            },
            templates: QuizEngine.skillTemplates, scopesSubjects: true),
        TeacherTopic(
            id: "buildings", label: "Buildings & Base", icon: "house.fill",
            elementIcon: nil, tint: .brown,
            entries: { data in
                ["base-building", "ranch", "cooking", "crafting", "breeding", "farming",
                 "generating-electricity", "cooling", "transporting", "technology"]
                    .compactMap { id in
                        data.articleByID[id].map {
                            StudyEntry(id: id, title: $0.title, subtitle: "Guide",
                                       icon: nil, kind: .articles)
                        }
                    }
            },
            templates: QuizEngine.buildingTemplates, scopesSubjects: false),
        TeacherTopic(
            id: "world", label: "World & Guides", icon: "globe.europe.africa.fill",
            elementIcon: nil, tint: .teal,
            entries: { data in
                // exactly the pages the trivia bank is written from
                Set(data.trivia.compactMap(\.articleID))
                    .compactMap { id in
                        data.articleByID[id].map {
                            StudyEntry(id: id, title: $0.title, subtitle: nil,
                                       icon: nil, kind: .articles)
                        }
                    }
                    .sorted { $0.title < $1.title }
            },
            templates: QuizEngine.worldTemplates, scopesSubjects: false),
    ]

    var body: some View {
        Form {
            Section("Questions") {
                Picker("Questions", selection: $count) {
                    ForEach([20, 40, 60, 80, 100], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Topics") {
                ForEach(Self.extraTopics) { topic in
                    topicRow(topic)
                }
            }
            Section("Pals by element") {
                ForEach(Theme.allElements, id: \.self) { element in
                    topicRow(Self.elementTopic(element))
                }
            }
        }
        .navigationTitle("Teacher")
    }

    private func topicRow(_ topic: TeacherTopic) -> some View {
        NavigationLink {
            TeacherStudyView(data: data, topic: topic, count: count)
        } label: {
            HStack(spacing: 10) {
                if let elementIcon = topic.elementIcon {
                    WikiImage(file: elementIcon, kind: .ui)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: topic.icon)
                        .foregroundStyle(topic.tint)
                        .frame(width: 24)
                }
                Text(topic.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(topic.tint)
                Spacer()
                Text("\(topic.entries(data).count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Study phase: the topic's pages, then "I'm ready".
struct TeacherStudyView: View {
    let data: GameData
    let topic: TeacherTopic
    let count: Int
    @Query private var profiles: [PlayerProfile]
    @State private var studyPageID: String?

    private var preferredDifficulty: Difficulty {
        Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "") ?? .medium
    }

    var body: some View {
        let entries = topic.entries(data)
        List {
            Section {
                Text("Read up before the quiz — tap any page to study it. Start whenever you feel ready.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("\(entries.count) pages to study") {
                ForEach(entries) { entry in
                    Button {
                        studyPageID = entry.id
                    } label: {
                        HStack(spacing: 10) {
                            if let icon = entry.icon {
                                WikiImage(file: icon, kind: entry.kind)
                                    .frame(width: 38, height: 38)
                            } else {
                                Image(systemName: "doc.text.fill")
                                    .font(.title3)
                                    .foregroundStyle(topic.tint)
                                    .frame(width: 38, height: 38)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let subtitle = entry.subtitle {
                                    Text(subtitle)
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
        .navigationTitle("\(topic.label) study hall")
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                QuizView(data: data,
                         questions: QuizEngine.makeSession(
                             data: data, count: count, difficulty: preferredDifficulty,
                             subjectIDs: topic.scopesSubjects ? entries.map(\.id) : nil,
                             templates: topic.templates),
                         difficulty: preferredDifficulty,
                         categoryLabel: "Teacher · \(topic.label)",
                         sessionMode: "teacher")
            } label: {
                Label("I'm ready — \(count) questions", systemImage: "graduationcap.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(topic.tint)
            .padding()
            .background(.bar)
        }
        .sheet(item: $studyPageID) { id in
            ArticleSheetView(data: data, articleID: id)
        }
    }
}
