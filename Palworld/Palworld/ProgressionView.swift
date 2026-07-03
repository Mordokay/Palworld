import SwiftUI
import SwiftData

/// The knowledge map (DESIGN.md §7): level + rank header, element-colored
/// completeness bars, expandable per-pal facet detail. Only "All Pals" can
/// launch a quiz — quizzes scoped to one pal or one element leak the answer
/// (every question would be about the same subject).
struct ProgressionView: View {
    let data: GameData
    @Query private var facetRecords: [FacetProgress]
    @Query private var profiles: [PlayerProfile]

    private var snapshot: ProgressionSnapshot { ProgressionSnapshot(records: facetRecords) }

    private func pals(for element: String) -> [Pal] {
        data.quizPals
            .filter { $0.elements.contains { $0.caseInsensitiveCompare(element) == .orderedSame } }
            .sorted { ($0.number.isEmpty ? "999" : $0.number) < ($1.number.isEmpty ? "999" : $1.number) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LevelHeaderView(xp: profiles.first?.xp ?? 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Pals by element") {
                    let allIDs = data.quizPals.map(\.id)
                    overallRow(label: "All Pals", color: .purple,
                               completeness: snapshot.completeness(entityIDs: allIDs),
                               subjects: data.quizPals)
                    ForEach(Theme.allElements, id: \.self) { element in
                        let members = pals(for: element)
                        if !members.isEmpty {
                            elementRow(element, members: members)
                        }
                    }
                }
            }
            .navigationTitle("Progression")
            .navigationDestination(for: QuizRequest.self) { request in
                QuizView(data: data,
                         questions: QuizEngine.makeSession(
                             data: data, count: 10,
                             difficulty: request.difficulty,
                             subjects: request.subjects(in: data)),
                         difficulty: request.difficulty,
                         categoryLabel: request.label)
            }
        }
    }

    private func overallRow(label: String, color: Color, completeness: Double,
                            subjects: [Pal]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.subheadline.weight(.bold))
                CompletenessBar(value: completeness, color: color)
            }
            Spacer()
            Text(completeness, format: .percent.precision(.fractionLength(0)))
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(color)
            quizButton(QuizRequest(label: label, palIDs: subjects.map(\.id)))
        }
    }

    private func elementRow(_ element: String, members: [Pal]) -> some View {
        DisclosureGroup {
            ForEach(members) { pal in
                palRow(pal)
            }
        } label: {
            HStack(spacing: 8) {
                WikiImage(file: Theme.elementIconFile(element), kind: .ui)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 6) {
                    Text(element).font(.subheadline.weight(.bold))
                    CompletenessBar(value: snapshot.completeness(entityIDs: members.map(\.id)),
                                    color: Theme.elementColor(element))
                }
                Spacer()
                Text(snapshot.completeness(entityIDs: members.map(\.id)),
                     format: .percent.precision(.fractionLength(0)))
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.elementColor(element))
            }
        }
    }

    private func palRow(_ pal: Pal) -> some View {
        HStack(spacing: 10) {
            WikiImage(file: pal.image, kind: .pals)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(pal.name).font(.caption.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach(Progression.palFacets, id: \.self) { facet in
                        facetDot(facet, net: snapshot.facets[pal.id]?[facet] ?? 0)
                    }
                }
            }
            Spacer()
            Text("\(snapshot.masteredFacetCount(entityID: pal.id))/\(Progression.palFacets.count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func facetDot(_ facet: String, net: Int) -> some View {
        let mastered = net >= Progression.masteryThreshold
        return HStack(spacing: 2) {
            Circle()
                .fill(mastered ? Color.green
                      : net > 0 ? Color.orange.opacity(0.7) : Color.gray.opacity(0.3))
                .frame(width: 7, height: 7)
            Text(facet)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func quizButton(_ request: QuizRequest) -> some View {
        NavigationLink(value: request) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// A targeted quiz launched from a progression gap.
struct QuizRequest: Hashable {
    let label: String
    let palIDs: [String]
    var difficulty: Difficulty = .medium

    func subjects(in data: GameData) -> [Pal] {
        palIDs.compactMap { data.palByID[$0] }
    }
}

struct CompletenessBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: max(6, proxy.size.width * value))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: 7)
    }
}

/// XP ring + rank badge shown at the top of Progression and Profile.
struct LevelHeaderView: View {
    let xp: Int

    var body: some View {
        let info = Progression.level(forXP: xp)
        let rank = Progression.rank(forLevel: info.level)
        let color = Progression.rankColor(forLevel: info.level)
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(info.progress) / Double(info.needed))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(info.level)")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("LVL")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text(rank)
                    .font(.headline)
                    .foregroundStyle(color)
                Label("\(xp) XP total", systemImage: Theme.Stat.xp.symbol)
                    .font(.caption)
                    .foregroundStyle(Theme.Stat.xp.color)
                Text("\(info.progress) / \(info.needed) to level \(info.level + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding()
    }
}
