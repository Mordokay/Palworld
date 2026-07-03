import Foundation

// MARK: - Models mirroring data/*.json (produced by pipeline/parse.py)

struct Pal: Codable, Identifiable, Hashable {
    struct PartnerSkill: Codable, Hashable {
        let name: String
        let icon: String
        let description: String
    }

    struct Stats: Codable, Hashable {
        let hp: Int?
        let attack: Int?
        let defense: Int?
        let hpLv50Range: [Int?]
        let attackLv50Range: [Int?]
        let defenseLv50Range: [Int?]
    }

    struct LearnedSkill: Codable, Hashable {
        let name: String
        let level: Int?
    }

    let id: String
    let name: String
    let number: String
    let image: String
    let elements: [String]
    let alphaTitle: String
    let partnerSkill: PartnerSkill
    let workSuitability: [String: Int]
    let foodAmount: Int?
    let breedPower: Int?
    let drops: [String]
    let alphaDrops: [String]
    let farmingProduce: [String]
    let habitatDay: String?
    let habitatNight: String?
    let saddleTech: String?
    let saddleTechLevel: Int?
    let stats: Stats?
    let activeSkills: [LearnedSkill]
    let paldeckEntry: String
    let categories: [String]
}

/// Shared shape of items.json and weapons.json.
struct Item: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let type: String
    let description: String
    let rarity: String
    let source: [String]
    let craftMaterials: [String]
    let weight: Double?
    let techTier: Int?
    let techPointsCost: Int?
    let workload: Double?
    let goldBuy: Int?
    let goldSell: Double?
    let nutrition: Int?
    let sanity: Int?
    let damage: Int?
    let durability: Int?
    let magazineSize: Int?
    let capturePower: Int?
    let categories: [String]
}

struct Skill: Codable, Identifiable, Hashable {
    struct SkillFruit: Codable, Hashable {
        let name: String
        let icon: String
    }

    struct LearnsetEntry: Codable, Hashable {
        let pal: String
        let level: Int?
    }

    let id: String
    let name: String
    let skillType: String
    let element: String
    let description: String
    let power: Int?
    let cooldown: Int?
    let range: String?
    let image: String?
    let skillFruit: SkillFruit?
    let exclusiveTo: [String]
    let learnset: [LearnsetEntry]
    let categories: [String]
}

struct Location: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let type: String
    let region: String
    let inhabitants: [String]
    let level: String
    let categories: [String]
}

/// Every wiki page as cleaned readable text — powers the Library and info sheets.
struct Article: Codable, Identifiable, Hashable {
    struct Table: Codable, Hashable {
        /// One table cell: text, optional link target (article id), optional icon.
        struct Cell: Codable, Hashable {
            let t: String
            var l: String?
            var img: String?
        }

        let headers: [String]
        let rows: [[Cell]]
    }

    struct SectionImage: Codable, Hashable {
        let file: String
        let caption: String
    }

    struct Section: Codable, Hashable {
        let heading: String
        /// 2 = top-level wiki section, 3 = sub-section
        let level: Int?
        let text: String
        /// Structured wikitables extracted from this section (weapon rarity
        /// tiers, element effectiveness charts, spawn tables...).
        let tables: [Table]?
        /// Display images the wiki shows in this section (galleries, maps...).
        let images: [SectionImage]?
    }

    let id: String
    let title: String
    let kind: String  // pal | item | weapon | skill | location | article
    let categories: [String]
    let sections: [Section]
}

/// One unlockable technology from the tech tree (technology.json).
struct TechEntry: Codable, Hashable {
    let level: Int
    let name: String
    let image: String
    let structure: Bool
    let points: Int
    let ancient: Bool
}

// MARK: - Loader

/// All bundled game data, loaded once at launch. Question templates and the
/// Library read from here; nothing touches the network.
struct GameData {
    let pals: [Pal]
    let items: [Item]
    let weapons: [Item]
    let skills: [Skill]
    let locations: [Location]
    let technology: [TechEntry]
    let articles: [Article]

    let palByID: [String: Pal]
    let articleByID: [String: Article]
    /// items and weapons share one index (same shape, both are "things")
    let itemByID: [String: Item]
    let skillByID: [String: Skill]
    /// lowercased entity/article title -> article id, for cross-linking
    let idByName: [String: String]

    /// Pals eligible for quiz questions. The wiki carries placeholder pages for
    /// teased-but-unreleased pals (no paldeck number, no lore, teaser images);
    /// they stay browsable in the Library but never become questions.
    var quizPals: [Pal] {
        pals.filter { !$0.number.isEmpty || !$0.paldeckEntry.isEmpty }
    }

    /// Resolve a decorated reference like "1-3 Wool (100%)", "40 Refined Ingot"
    /// or "Ring of Resistance +1 - 3%" to the linked entity's article id.
    func resolveEntityName(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[\d,.\-–x× ]+"#, with: "", options: .regularExpression)
        if let id = idByName[s.lowercased()] { return id }
        // drop trailing decorations: " - (2-3) 100%", " +1 - 3%", " 100%"
        if let cut = s.range(of: " - ") {
            s = String(s[..<cut.lowerBound])
        }
        s = s.replacingOccurrences(of: #"\s*(\+\d+|\d+%|\(\d[^)]*\))\s*$"#, with: "",
                                   options: .regularExpression)
        return idByName[s.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Breadcrumb bubble for a navigation route: title + a small icon when the
    /// target is an entity with an image.
    func trailItem(for route: String) -> BreadcrumbView.Item {
        if route.hasPrefix("section:") {
            let name = String(route.dropFirst(8))
            return .init(label: name.capitalized, icon: nil)
        }
        let label = articleByID[route]?.title ?? route
        var icon = palByID[route]?.image ?? itemByID[route]?.image
        if icon == nil, Theme.allElements.contains(where: { $0.lowercased() == route }) {
            icon = Theme.elementIconFile(route.capitalized)
        }
        return .init(label: label, icon: icon)
    }

    /// Display name (sans decorations) for a drops/materials line.
    static func strippedName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        return s
    }

    enum ImageKind: String {
        case pals, items, weapons, skills, locations, ui, maps, articles, misc
    }

    /// filename -> subfolder, built once by scanning the bundled images. This
    /// makes lookups independent of which folder an image was downloaded into
    /// (classification of entities can shift between data refreshes).
    private static let imageFolderIndex: [String: String] = {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("data/images")
        else { return [:] }
        var index: [String: String] = [:]
        let fm = FileManager.default
        for folder in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let folderURL = root.appendingPathComponent(folder)
            for file in (try? fm.contentsOfDirectory(atPath: folderURL.path)) ?? [] {
                index[file] = folder
            }
        }
        return index
    }()

    /// URL of a bundled wiki image; `kind` is only a fallback hint.
    static func imageURL(_ filename: String, kind: ImageKind) -> URL? {
        // fetch_images.py canonicalizes names: no File: prefix, spaces not underscores
        var name = filename.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("File:") { name = String(name.dropFirst(5)) }
        let folder = Self.imageFolderIndex[name] ?? kind.rawValue
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("data/images/\(folder)/\(name)"),
            FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func load() throws -> GameData {
        func decode<T: Decodable>(_ file: String) throws -> [T] {
            guard let url = Bundle.main.url(
                forResource: file, withExtension: "json", subdirectory: "data"
            ) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "data/\(file).json"])
            }
            return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
        }

        let pals: [Pal] = try decode("pals")
        let items: [Item] = try decode("items")
        let weapons: [Item] = try decode("weapons")
        let skills: [Skill] = try decode("skills")
        let articles: [Article] = try decode("articles")

        var idByName: [String: String] = [:]
        for article in articles {
            idByName[article.title.lowercased()] = article.id
        }
        return GameData(
            pals: pals,
            items: items,
            weapons: weapons,
            skills: skills,
            locations: try decode("locations"),
            technology: try decode("technology"),
            articles: articles,
            palByID: Dictionary(uniqueKeysWithValues: pals.map { ($0.id, $0) }),
            articleByID: Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) }),
            itemByID: Dictionary((items + weapons).map { ($0.id, $0) },
                                 uniquingKeysWith: { a, _ in a }),
            skillByID: Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) }),
            idByName: idByName
        )
    }
}
