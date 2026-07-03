import SwiftUI

/// Central lookup for the app's colorful identity: element colors, stat colors
/// and symbols (see DESIGN.md §10). Use these everywhere — never ad-hoc colors.
enum Theme {
    static func elementColor(_ element: String) -> Color {
        switch element.lowercased() {
        case "neutral": Color(red: 0.66, green: 0.64, blue: 0.62)
        case "fire": Color(red: 0.94, green: 0.27, blue: 0.27)
        case "water": Color(red: 0.23, green: 0.51, blue: 0.96)
        case "grass": Color(red: 0.13, green: 0.77, blue: 0.37)
        case "electric": Color(red: 0.98, green: 0.80, blue: 0.08)
        case "ice": Color(red: 0.49, green: 0.83, blue: 0.99)
        case "ground": Color(red: 0.85, green: 0.47, blue: 0.02)
        case "dark": Color(red: 0.49, green: 0.23, blue: 0.93)
        case "dragon": Color(red: 0.39, green: 0.40, blue: 0.95)
        default: .secondary
        }
    }

    /// Bundled game icon for an element (data/images/ui/).
    static func elementIconFile(_ element: String) -> String {
        "\(element.capitalized) icon.png"
    }

    /// Bundled game icon for a work-suitability key from pals.json.
    static func workIconFile(_ workKey: String) -> String {
        let name = workKey.replacingOccurrences(
            of: #"([A-Z])"#, with: " $1", options: .regularExpression
        ).capitalized.trimmingCharacters(in: .whitespaces)
        return "\(name) Icon.png"
    }

    static func workLabel(_ workKey: String) -> String {
        workKey.replacingOccurrences(of: #"([A-Z])"#, with: " $1", options: .regularExpression)
            .capitalized.trimmingCharacters(in: .whitespaces)
    }

    /// Damage-taken multipliers: [defending element: [attacking element: x]].
    /// Values from the wiki's Pal Element Effect template; absent pairs are 1x.
    /// Dual-element pals multiply their elements' values.
    static let damageTaken: [String: [String: Double]] = [
        "neutral": ["dark": 1.5],
        "fire": ["water": 1.5, "grass": 0.5, "ice": 0.5],
        "water": ["electric": 1.5, "fire": 0.5],
        "grass": ["fire": 1.5, "ground": 0.5],
        "electric": ["ground": 1.5, "water": 0.5],
        "ice": ["fire": 1.5, "dragon": 0.5],
        "ground": ["grass": 1.5, "electric": 0.5],
        "dark": ["dragon": 1.5, "neutral": 0.5],
        "dragon": ["ice": 1.5, "dark": 0.5],
    ]

    static let allElements = ["Neutral", "Fire", "Water", "Grass", "Electric",
                              "Ice", "Ground", "Dark", "Dragon"]

    /// How much damage a pal with `elements` takes from an attack of `attacker`.
    static func damageMultiplier(defender elements: [String], attacker: String) -> Double {
        elements.reduce(1.0) { result, element in
            result * (damageTaken[element.lowercased()]?[attacker.lowercased()] ?? 1)
        }
    }

    enum Stat {
        case hp, attack, defense, work, food, gold, xp

        var color: Color {
            switch self {
            case .hp: .green
            case .attack: .red
            case .defense: .blue
            case .work: .teal
            case .food: .brown
            case .gold: .orange
            case .xp: .purple
            }
        }

        var symbol: String {
            switch self {
            case .hp: "heart.fill"
            case .attack: "flame.fill"
            case .defense: "shield.fill"
            case .work: "hammer.fill"
            case .food: "fork.knife"
            case .gold: "dollarsign.circle.fill"
            case .xp: "star.fill"
            }
        }
    }
}

/// Capsule chip for an element type — game icon + 20% tinted background.
struct ElementChip: View {
    let element: String

    var body: some View {
        HStack(spacing: 4) {
            WikiImage(file: Theme.elementIconFile(element), kind: .ui)
                .frame(width: 16, height: 16)
            Text(element)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.elementColor(element).opacity(0.2), in: Capsule())
        .foregroundStyle(Theme.elementColor(element))
    }
}

/// Bundled wiki image, loaded from data/images/<kind>/.
struct WikiImage: View {
    let file: String
    let kind: GameData.ImageKind

    var body: some View {
        if let url = GameData.imageURL(file, kind: kind),
           let ui = UIImage(contentsOfFile: url.path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        } else {
            // a few wiki entries have no uploaded image yet (e.g. new 1.0
            // content) — show a clean placeholder instead of an empty gap
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .padding(22)
                .foregroundStyle(.tertiary)
        }
    }
}
