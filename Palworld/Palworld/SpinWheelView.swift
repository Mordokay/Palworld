import SwiftUI
import SwiftData

/// One wheel segment: a question topic backed by a single template.
struct WheelTopic {
    let label: String
    let icon: String
    let color: Color
    let facet: String
    let template: any QuestionTemplate
}

/// Spin the Wheel (DESIGN.md §5): zero-decision play. The wheel is honest to
/// look at but secretly weighted — facets you're weakest in come up more.
/// Topic-per-template (not per-element) so a landed topic never telegraphs
/// its own answers.
struct SpinWheelView: View {
    let data: GameData
    @Query private var facetRecords: [FacetProgress]
    @Query private var profiles: [PlayerProfile]

    @State private var rotation = 0.0
    @State private var spinning = false
    @State private var landed: Int?

    private static let topics: [WheelTopic] = [
        WheelTopic(label: "Spot the Pal", icon: "photo.fill", color: .blue,
                   facet: "identify", template: PictureToNameTemplate()),
        WheelTopic(label: "Elements", icon: "flame.fill", color: .orange,
                   facet: "elements", template: PalElementTemplate()),
        WheelTopic(label: "Lore", icon: "book.fill", color: .purple,
                   facet: "lore", template: LoreToPalTemplate()),
        WheelTopic(label: "Drops", icon: "shippingbox.fill", color: .brown,
                   facet: "drops", template: PalDropsTemplate()),
        WheelTopic(label: "Stat Duels", icon: "chart.bar.fill", color: .green,
                   facet: "stats", template: StatDuelTemplate()),
        WheelTopic(label: "Find the Pal", icon: "magnifyingglass", color: .teal,
                   facet: "identify", template: NameToPictureTemplate()),
        WheelTopic(label: "Work", icon: "hammer.fill", color: .cyan,
                   facet: "work", template: WorkSuitabilityTemplate()),
        WheelTopic(label: "Alpha Titles", icon: "crown.fill", color: .red,
                   facet: "lore", template: AlphaTitleTemplate()),
        WheelTopic(label: "Active Skills", icon: "bolt.circle.fill", color: .mint,
                   facet: "skills", template: ActiveSkillTemplate()),
        WheelTopic(label: "Partner Skills", icon: "person.2.fill", color: .pink,
                   facet: "partnerSkill", template: PartnerSkillTemplate()),
        WheelTopic(label: "Silhouettes", icon: "moon.stars.fill", color: .indigo,
                   facet: "identify", template: SilhouetteTemplate()),
        WheelTopic(label: "Appetites", icon: "fork.knife", color: .yellow,
                   facet: "utility", template: FoodDuelTemplate()),
    ]

    private var step: Double { 360.0 / Double(Self.topics.count) }
    private var preferredDifficulty: Difficulty {
        Difficulty(rawValue: profiles.first?.preferredDifficulty ?? "") ?? .medium
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            wheel
            landedSection
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Spin the Wheel")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: landed)
    }

    // MARK: - Wheel

    private var wheel: some View {
        ZStack {
            ZStack {
                ForEach(Array(Self.topics.enumerated()), id: \.offset) { i, topic in
                    SectorShape(start: .degrees(Double(i) * step - 90),
                                end: .degrees(Double(i + 1) * step - 90))
                        .fill(topic.color.gradient)
                        .overlay(SectorShape(start: .degrees(Double(i) * step - 90),
                                             end: .degrees(Double(i + 1) * step - 90))
                            .stroke(.background, lineWidth: 3))
                }
                ForEach(Array(Self.topics.enumerated()), id: \.offset) { i, topic in
                    Image(systemName: topic.icon)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .offset(y: -104)
                        .rotationEffect(.degrees((Double(i) + 0.5) * step))
                }
            }
            .frame(width: 290, height: 290)
            .rotationEffect(.degrees(rotation))

            // hub doubles as the spin button
            Button(action: spin) {
                ZStack {
                    Circle()
                        .fill(.background)
                        .shadow(radius: 4)
                    Text(spinning ? "…" : "SPIN")
                        .font(.headline.weight(.black))
                        .foregroundStyle(spinning ? .secondary : .primary)
                }
                .frame(width: 78, height: 78)
            }
            .buttonStyle(.plain)
            .disabled(spinning)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.title)
                .foregroundStyle(.primary)
                .offset(y: -158)
        }
        .frame(width: 300, height: 330)
    }

    @ViewBuilder
    private var landedSection: some View {
        if let landed {
            let topic = Self.topics[landed]
            VStack(spacing: 12) {
                Label(topic.label, systemImage: topic.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(topic.color)
                NavigationLink {
                    QuizView(data: data,
                             questions: QuizEngine.makeSession(
                                 data: data, count: 5, difficulty: preferredDifficulty,
                                 templates: [topic.template]),
                             difficulty: preferredDifficulty,
                             categoryLabel: topic.label,
                             sessionMode: "wheel")
                } label: {
                    Text("Start · 5 questions")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(topic.color)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(topic.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(topic.color.opacity(0.35), lineWidth: 1))
        } else {
            Text(spinning ? "Round and round it goes…"
                 : "Spin to get 5 questions on a random topic")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 30)
        }
    }

    // MARK: - Spin

    private func spin() {
        guard !spinning else { return }
        spinning = true
        landed = nil
        let target = weightedPick()
        // land the target segment's center under the top pointer, with a bit
        // of in-segment jitter so identical results don't look scripted
        let jitter = Double.random(in: -0.32...0.32) * step
        let desired = -(Double(target) + 0.5) * step + jitter
        var delta = (desired - rotation).truncatingRemainder(dividingBy: 360)
        if delta < 0 { delta += 360 }
        let final = rotation + 4 * 360 + delta
        withAnimation(.easeOut(duration: 3)) {
            rotation = final
        }
        Task {
            try? await Task.sleep(for: .seconds(3.15))
            landed = target
            spinning = false
        }
    }

    /// Inverse-strength weights per facet: the less net-correct you have in a
    /// topic's facet, the likelier the wheel lands there.
    private func weightedPick() -> Int {
        var totals: [String: Int] = [:]
        for record in facetRecords {
            totals[record.facet, default: 0] += record.netCorrect
        }
        let weights = Self.topics.map { 1.0 / Double(1 + (totals[$0.facet] ?? 0)) }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        for (i, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 { return i }
        }
        return Self.topics.count - 1
    }
}

struct SectorShape: Shape {
    let start: Angle
    let end: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                    startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}
