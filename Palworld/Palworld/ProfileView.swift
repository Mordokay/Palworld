import SwiftUI
import SwiftData

/// Profile tab: identity (name + pal avatar with unlocks), level/rank,
/// quiz history with completion rings + replay, lifetime stats.
struct ProfileView: View {
    let data: GameData
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [PlayerProfile]
    @Query(sort: \QuizSession.date, order: .reverse) private var sessions: [QuizSession]
    @Query private var facetRecords: [FacetProgress]
    @State private var showAvatarPicker = false

    private var snapshot: ProgressionSnapshot { ProgressionSnapshot(records: facetRecords) }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                Section {
                    LevelHeaderView(xp: profiles.first?.xp ?? 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                statsSection
                historySection
            }
            .navigationTitle("Profile")
            .navigationDestination(for: QuizRequest.self) { request in
                QuizView(data: data,
                         questions: QuizEngine.makeSession(
                             data: data, count: 10, difficulty: request.difficulty,
                             subjectIDs: request.palIDs),
                         difficulty: request.difficulty,
                         categoryLabel: request.label)
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let session = modelContext.model(for: id) as? QuizSession {
                    SessionDetailView(data: data, session: session)
                }
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView(data: data, snapshot: snapshot) { palID in
                    profiles.first?.avatarPalID = palID
                }
            }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                Button {
                    showAvatarPicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        WikiImage(file: data.palByID[profiles.first?.avatarPalID ?? "lamball"]?.image ?? "",
                                  kind: .pals)
                            .frame(width: 64, height: 64)
                            .padding(6)
                            .background(.teal.opacity(0.12), in: Circle())
                        Image(systemName: "pencil.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tint)
                            .background(Circle().fill(.background))
                    }
                }
                .buttonStyle(.plain)
                TextField("Trainer name", text: Binding(
                    get: { profiles.first?.name ?? "Trainer" },
                    set: { profiles.first?.name = $0 }
                ))
                .font(.title3.bold())
            }
            .padding(.vertical, 4)
        }
    }

    private var statsSection: some View {
        let totalQuestions = sessions.reduce(0) { $0 + $1.signatures.count }
        let totalCorrect = sessions.reduce(0) { $0 + $1.bestScore }
        let mastered = data.quizPals.filter {
            snapshot.masteredFacetCount(pal: $0) == Progression.facets(for: $0).count
        }.count
        return Section("Stats") {
            LabeledContent("Quizzes played", value: "\(sessions.count)")
            LabeledContent("Questions answered", value: "\(totalQuestions)")
            LabeledContent("Best-run correct answers", value: "\(totalCorrect)")
            LabeledContent("Pals fully mastered", value: "\(mastered)/\(data.quizPals.count)")
            NavigationLink {
                PlacementTestView(data: data)
            } label: {
                LabeledContent("Preferred difficulty") {
                    Text((Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "")
                          ?? .medium).label)
                    Text("· retake test")
                        .foregroundStyle(.tint)
                }
                .font(.subheadline)
            }
        }
    }

    private var historySection: some View {
        Section("Quiz History") {
            if sessions.isEmpty {
                Text("Play a quiz and it will appear here — every quiz can be replayed until all its questions are green.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                NavigationLink(value: session.persistentModelID) {
                    HStack(spacing: 12) {
                        if session.signatures.isEmpty {
                            // streak runs (Higher/Lower) have no question sheet
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.orange)
                                .frame(width: 34, height: 34)
                        } else {
                            CompletionRing(session: session)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.categoryLabel)
                                .font(.subheadline.weight(.semibold))
                            Text("\(session.date, format: .dateTime.day().month().hour().minute()) · \(session.difficulty.capitalized)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.signatures.isEmpty
                             ? "×\(session.bestScore)"
                             : "\(session.bestScore)/\(session.signatures.count)")
                            .font(.caption.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(session.completion == 1 ? .green : .secondary)
                    }
                }
            }
        }
    }
}

/// Green/red segmented ring: which of a session's questions were EVER right.
struct CompletionRing: View {
    let session: QuizSession

    var body: some View {
        let n = max(session.everCorrect.count, 1)
        ZStack {
            ForEach(0..<n, id: \.self) { i in
                Circle()
                    .trim(from: Double(i) / Double(n) + 0.008,
                          to: Double(i + 1) / Double(n) - 0.008)
                    .stroke(session.everCorrect.indices.contains(i) && session.everCorrect[i]
                            ? Color.green : Color.red.opacity(0.55),
                            style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            if session.completion == 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 34, height: 34)
    }
}

/// Past-quiz detail: per-question review + replay.
struct SessionDetailView: View {
    let data: GameData
    let session: QuizSession

    var body: some View {
        List {
            if session.signatures.isEmpty {
                // Higher/Lower run: only the streak is meaningful
                Section {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("Streak of \(session.bestScore)")
                                .font(.headline)
                            Text("\(session.xpEarned) XP earned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
            Section {
                HStack {
                    CompletionRing(session: session)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("\(Int(session.completion * 100))% complete")
                            .font(.headline)
                        Text("Best \(session.bestScore)/\(session.signatures.count) · \(session.xpEarned) XP earned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                NavigationLink(value: ReplayRequest(sessionID: session.persistentModelID)) {
                    Label(session.completion == 1 ? "Replay (no XP left to earn)"
                          : "Replay — turn the reds green for 2× XP",
                          systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Section("Questions") {
                ForEach(Array(session.signatures.enumerated()), id: \.offset) { i, signature in
                    let subjectID = signature.split(separator: "|").last.map(String.init) ?? ""
                    // subjects can be pals, items or skills since M6
                    let icon = data.palByID[subjectID]?.image
                        ?? data.itemByID[subjectID]?.image
                        ?? data.skillByID[subjectID]?.image
                    HStack(spacing: 10) {
                        Image(systemName: session.everCorrect.indices.contains(i) && session.everCorrect[i]
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(session.everCorrect.indices.contains(i) && session.everCorrect[i]
                                             ? .green : .red)
                        WikiImage(file: icon ?? "", kind: .pals)
                            .frame(width: 26, height: 26)
                        Text(data.articleByID[subjectID]?.title ?? subjectID)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(signature.split(separator: "|").first?
                            .split(separator: ".").last.map(String.init) ?? "")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            }
        }
        .navigationTitle(session.categoryLabel)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ReplayRequest.self) { request in
            ReplayLoaderView(data: data, session: session)
        }
    }
}

struct ReplayRequest: Hashable {
    let sessionID: PersistentIdentifier
}

/// Regenerates a session's questions from signatures, then runs the quiz.
struct ReplayLoaderView: View {
    let data: GameData
    let session: QuizSession

    var body: some View {
        let difficulty = Difficulty(rawValue: session.difficulty) ?? .medium
        QuizView(data: data,
                 questions: QuizEngine.regenerate(data: data,
                                                  signatures: session.signatures,
                                                  difficulty: difficulty),
                 difficulty: difficulty,
                 categoryLabel: session.categoryLabel,
                 replayOf: session)
    }
}

/// Pick any pal you've "caught" (5 correct answers about it) as your avatar.
struct AvatarPickerView: View {
    let data: GameData
    let snapshot: ProgressionSnapshot
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let unlockThreshold = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                          spacing: 10) {
                    ForEach(data.quizPals) { pal in
                        let unlocked = pal.id == "lamball"
                            || snapshot.totalCorrect(entityID: pal.id) >= Self.unlockThreshold
                        Button {
                            onPick(pal.id)
                            dismiss()
                        } label: {
                            VStack(spacing: 3) {
                                WikiImage(file: pal.image, kind: .pals)
                                    .frame(height: 56)
                                    .grayscale(unlocked ? 0 : 1)
                                    .opacity(unlocked ? 1 : 0.35)
                                Text(unlocked ? pal.name
                                     : "\(snapshot.totalCorrect(entityID: pal.id))/\(Self.unlockThreshold)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(unlocked ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .padding(6)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(!unlocked)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
