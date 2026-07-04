import SwiftUI
import SwiftData

/// Unlock timestamp for an earned achievement (conditions are re-derived
/// from progression data; only the "when" needs persisting).
@Model
final class AchievementState {
    var achievementID: String = ""
    var unlockedAt: Date = Date()

    init(achievementID: String) {
        self.achievementID = achievementID
    }
}

/// Everything an achievement condition can look at.
struct AchievementContext {
    let data: GameData
    let sessions: [QuizSession]
    let missRecords: [MissRecord]
    let snapshot: ProgressionSnapshot
}

struct AchievementDef: Identifiable {
    let id: String
    let title: String
    let hint: String
    let symbol: String
    let tint: Color
    /// (current, target) — unlocked when current ≥ target.
    let progress: (AchievementContext) -> (current: Int, target: Int)
}

@MainActor
enum Achievements {
    /// DESIGN.md §8: the placeholder five, with Hydrologist generalized into
    /// an element-mastery family so every element has its trophy.
    static let all: [AchievementDef] = [
        AchievementDef(
            id: "first-steps", title: "First Steps",
            hint: "Finish your first quiz", symbol: "figure.walk", tint: .green,
            progress: { (min($0.sessions.count, 1), 1) }),
        AchievementDef(
            id: "on-fire", title: "On Fire",
            hint: "Answer 10 in a row correctly in one quiz", symbol: "flame.fill",
            tint: .orange,
            progress: { context in
                let best = context.sessions.map { longestRun($0.lastCorrect) }.max() ?? 0
                return (min(best, 10), 10)
            }),
        AchievementDef(
            id: "creature-of-habit", title: "Creature of Habit",
            hint: "Keep a 7-day Daily Challenge streak", symbol: "calendar", tint: .yellow,
            progress: { (min(Progression.dailyStreak(sessions: $0.sessions), 7), 7) }),
        AchievementDef(
            id: "making-amends", title: "Making Amends",
            hint: "Redeem 25 previously missed questions",
            symbol: "arrow.uturn.up.circle.fill", tint: .purple,
            progress: { (min($0.missRecords.filter(\.redeemed).count, 25), 25) }),
    ] + elementFamily

    /// "Hydrologist" for Water, and siblings for every element: 100%
    /// completeness across all of the element's pals.
    private static let elementTitles: [String: (String, String)] = [
        "Water": ("Hydrologist", "drop.fill"),
        "Fire": ("Pyrotechnician", "flame.circle.fill"),
        "Grass": ("Botanist", "leaf.fill"),
        "Electric": ("Electrician", "bolt.fill"),
        "Ice": ("Glaciologist", "snowflake"),
        "Ground": ("Geologist", "mountain.2.fill"),
        "Dark": ("Night Owl", "moon.fill"),
        "Dragon": ("Dragonologist", "lizard.fill"),
        "Neutral": ("All-Rounder", "circle.grid.cross.fill"),
    ]

    private static var elementFamily: [AchievementDef] {
        Theme.allElements.compactMap { element in
            guard let (title, symbol) = elementTitles[element] else { return nil }
            return AchievementDef(
                id: "master-\(element.lowercased())", title: title,
                hint: "Fully master every \(element) pal", symbol: symbol,
                tint: Theme.elementColor(element),
                progress: { context in
                    let members = context.data.quizPals.filter {
                        $0.elements.contains(element)
                    }
                    let pct = context.snapshot.completeness(pals: members) * 100
                    return (Int(pct), 100)
                })
        }
    }

    static func longestRun(_ results: [Bool]) -> Int {
        var best = 0, current = 0
        for correct in results {
            current = correct ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    /// Persist any freshly-earned unlocks; returns them for celebration.
    @discardableResult
    static func evaluate(context: AchievementContext,
                         modelContext: ModelContext) -> [AchievementDef] {
        let unlocked = Set(((try? modelContext.fetch(FetchDescriptor<AchievementState>()))
            ?? []).map(\.achievementID))
        var fresh: [AchievementDef] = []
        for def in all where !unlocked.contains(def.id) {
            let (current, target) = def.progress(context)
            if current >= target {
                modelContext.insert(AchievementState(achievementID: def.id))
                fresh.append(def)
            }
        }
        return fresh
    }
}

// MARK: - Tab

struct AchievementsView: View {
    let data: GameData
    @Environment(\.modelContext) private var modelContext
    @Query private var states: [AchievementState]
    @Query private var sessions: [QuizSession]
    @Query private var missRecords: [MissRecord]
    @Query private var facetRecords: [FacetProgress]

    private var context: AchievementContext {
        AchievementContext(data: data, sessions: sessions, missRecords: missRecords,
                           snapshot: ProgressionSnapshot(records: facetRecords))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let ctx = context
                let unlockedAt = Dictionary(states.map { ($0.achievementID, $0.unlockedAt) },
                                            uniquingKeysWith: { a, _ in a })
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 12) {
                    ForEach(Achievements.all) { def in
                        AchievementCard(def: def,
                                        unlockedAt: unlockedAt[def.id],
                                        progress: def.progress(ctx))
                    }
                }
                .padding()
            }
            .navigationTitle("Achievements")
            .onAppear {
                // catch conditions met outside a quiz (e.g. a streak maturing)
                Achievements.evaluate(context: context, modelContext: modelContext)
            }
        }
    }
}

struct AchievementCard: View {
    let def: AchievementDef
    let unlockedAt: Date?
    let progress: (current: Int, target: Int)

    private var unlocked: Bool { unlockedAt != nil }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: def.symbol)
                .font(.system(size: 34))
                .foregroundStyle(unlocked ? AnyShapeStyle(def.tint)
                                          : AnyShapeStyle(.tertiary))
                .frame(height: 44)
            Text(def.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(unlocked ? .primary : .secondary)
            Text(def.hint)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            if let unlockedAt {
                Text(unlockedAt, style: .date)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(def.tint)
            } else {
                ProgressView(value: Double(progress.current),
                             total: Double(max(progress.target, 1)))
                    .tint(def.tint)
                Text("\(progress.current)/\(progress.target)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(unlocked ? AnyShapeStyle(def.tint.opacity(0.10))
                             : AnyShapeStyle(.background.secondary),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(unlocked ? def.tint.opacity(0.4) : .clear, lineWidth: 1))
        .opacity(unlocked ? 1 : 0.75)
    }
}

// MARK: - Confetti (perfect scores, unlocks, level-ups)

/// Two confetti cannons in the bottom corners: pieces launch up and inward,
/// arc over under gravity, and flutter down. Units are height-relative so it
/// looks the same on any screen.
struct ConfettiView: View {
    private struct Particle {
        let fromLeft: Bool
        let delay: Double
        /// launch angle above horizontal (radians), aimed into the screen
        let angle: Double
        /// launch speed, in screen-heights per second
        let speed: Double
        let wobble: Double
        let phase: Double
        let size: Double
        let color: Color
        let spin: Double

        static func random(fromLeft: Bool) -> Particle {
            Particle(fromLeft: fromLeft,
                     delay: .random(in: 0...0.45),
                     angle: .random(in: (.pi * 0.28)...(.pi * 0.42)),  // 50°–75°
                     speed: .random(in: 1.15...1.65),
                     wobble: .random(in: 8...26),
                     phase: .random(in: 0...(2 * .pi)),
                     size: .random(in: 6...11),
                     color: [.red, .orange, .yellow, .green, .teal, .blue, .purple,
                             .pink].randomElement()!,
                     spin: .random(in: 3...9))
        }
    }

    private let particles = (0..<45).map { _ in Particle.random(fromLeft: true) }
        + (0..<45).map { _ in Particle.random(fromLeft: false) }
    private let start = Date()
    private let duration = 4.0
    /// gravity, in screen-heights per second²
    private let gravity = 1.35

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                for particle in particles {
                    let life = t - particle.delay
                    guard life > 0 else { continue }
                    // projectile motion from a bottom corner, inward + up
                    let v = particle.speed * size.height
                    let vx = cos(particle.angle) * v * (particle.fromLeft ? 1 : -1)
                    let vy = sin(particle.angle) * v
                    let x0 = particle.fromLeft ? -12.0 : size.width + 12.0
                    let x = x0 + vx * life
                        + sin(life * 4 + particle.phase) * particle.wobble
                    let y = size.height + 12 - vy * life
                        + 0.5 * gravity * size.height * life * life
                    guard y < size.height + 24 else { continue }
                    context.opacity = min(1, max(0, (duration - t) / 0.8))
                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(life * particle.spin))
                        layer.fill(
                            Path(roundedRect: CGRect(x: -particle.size / 2,
                                                     y: -particle.size / 3,
                                                     width: particle.size,
                                                     height: particle.size * 0.66),
                                 cornerRadius: 1.5),
                            with: .color(particle.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
