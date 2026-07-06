import SwiftUI

/// Renders the Library page for any entity/article id: typed detail card on
/// top (pal / item / skill), then the article's readable sections with
/// tappable entity names. Navigation between pages uses String ids pushed onto
/// the enclosing NavigationStack (which must declare
/// `.navigationDestination(for: String.self)`).
struct EntityPageView: View {
    let data: GameData
    let id: String
    @State private var zoomImage: ZoomTarget?

    struct ZoomTarget: Identifiable {
        let file: String
        let kind: GameData.ImageKind
        var id: String { file }
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollContent
                .onAppear {
                    guard CommandLine.arguments.contains("-scroll-bottom") else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { proxy.scrollTo("pageBottom", anchor: .bottom) }
                    }
                }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if id == "technology" {
                    TechnologyTreeView(data: data)
                } else if id == "breeding" {
                    BreedingCalculatorView(data: data)
                    if let article = data.articleByID[id] {
                        articleSections(article)
                    }
                } else if id == "base-building" {
                    if let article = data.articleByID[id] {
                        articleSections(article)
                    }
                    BuildCatalogView(data: data)
                } else if Theme.allElements.contains(where: { $0.lowercased() == id }) {
                    ElementPageView(data: data, element: id.capitalized)
                } else {
                    if let pal = data.palByID[id] {
                        palCard(pal)
                    } else if let item = data.itemByID[id] {
                        itemCard(item)
                    } else if let skill = data.skillByID[id] {
                        skillCard(skill)
                    } else if let location = data.locations.first(where: { $0.id == id }) {
                        locationCard(location)
                    }
                    if let article = data.articleByID[id] {
                        articleSections(article)
                    }
                }
                Color.clear.frame(height: 1).id("pageBottom")
            }
            .padding()
        }
        .navigationTitle(data.articleByID[id]?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $zoomImage) { target in
            ZoomableImageView(file: target.file, kind: target.kind)
        }
    }

    /// Pal page sections whose content the structured card above already
    /// presents better — showing them twice reads as JSON-dump clutter.
    private static let palRedundantHeadings: Set<String> = [
        "paldeck entry", "stats", "utility", "active skills",
        "elemental effectiveness", "breeding",
    ]

    // MARK: Pal

    @ViewBuilder
    private func palCard(_ pal: Pal) -> some View {
        VStack(spacing: 10) {
            WikiImage(file: pal.image, kind: .pals)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { zoomImage = ZoomTarget(file: pal.image, kind: .pals) }
            HStack(spacing: 8) {
                if !pal.number.isEmpty {
                    Text("#\(pal.number)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                ForEach(pal.elements, id: \.self) { element in
                    NavigationLink(value: element.lowercased()) {
                        ElementChip(element: element)
                    }
                }
            }
            if !pal.alphaTitle.isEmpty {
                Text(pal.alphaTitle)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)

        // some pals (incl. wiki "???" stats) have no numbers — hide the card
        if let stats = pal.stats,
           stats.hp != nil || stats.attack != nil || stats.defense != nil {
            HStack(spacing: 0) {
                statColumn(.hp, base: stats.hp, range: stats.hpLv50Range)
                statColumn(.attack, base: stats.attack, range: stats.attackLv50Range)
                statColumn(.defense, base: stats.defense, range: stats.defenseLv50Range)
            }
            .padding(.vertical, 10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }

        if !pal.partnerSkill.name.isEmpty {
            section("Partner Skill") {
                Text(pal.partnerSkill.name).font(.subheadline.weight(.bold))
                Text(pal.partnerSkill.description).font(.callout)
            }
        }

        if let food = pal.foodAmount {
            section("Food") {
                HStack(spacing: 3) {
                    // the wiki's "off" icon is white-on-transparent (invisible in
                    // light mode) — dimming the filled icon works in both themes
                    ForEach(0..<10, id: \.self) { slot in
                        WikiImage(file: "Food_on_icon.png", kind: .ui)
                            .grayscale(slot < food ? 0 : 1)
                            .opacity(slot < food ? 1 : 0.25)
                            .frame(width: 22, height: 22)
                    }
                    Text("\(food)/10")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
            }
        }

        if !pal.workSuitability.isEmpty {
            section("Work Suitability") {
                FlowLayout(spacing: 6) {
                    ForEach(pal.workSuitability.sorted { $0.value > $1.value }, id: \.key) { work in
                        HStack(spacing: 5) {
                            WikiImage(file: Theme.workIconFile(work.key), kind: .ui)
                                .frame(width: 18, height: 18)
                            Text(Theme.workLabel(work.key))
                                .font(.caption.weight(.bold))
                            Text(String(repeating: "★", count: work.value))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.teal.opacity(0.12), in: Capsule())
                    }
                }
            }
        }

        if !pal.drops.isEmpty {
            section("Drops") { entityChips(pal.drops) }
        }
        if !pal.alphaDrops.isEmpty {
            section("Alpha Drops") { entityChips(pal.alphaDrops) }
        }
        if !pal.farmingProduce.isEmpty {
            section("Farming Produce") { entityChips(pal.farmingProduce) }
        }

        if pal.habitatDay != nil || pal.habitatNight != nil {
            section("Habitat") {
                HabitatView(pal: pal) { file in
                    zoomImage = ZoomTarget(file: file, kind: .maps)
                }
            }
        }

        if !pal.elements.isEmpty {
            section("Elemental Effectiveness") {
                ElementEffectivenessView(elements: pal.elements)
            }
        }

        if !pal.activeSkills.isEmpty {
            section("Active Skills") {
                VStack(spacing: 8) {
                    ForEach(pal.activeSkills, id: \.self) { learned in
                        activeSkillRow(learned)
                    }
                }
            }
        }

        if let tech = pal.saddleTech {
            section("Mount") {
                HStack(spacing: 6) {
                    entityChips([tech])
                    if let level = pal.saddleTechLevel {
                        Text("Tech \(level)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Wiki-style active skill row: element-colored level badge, name,
    /// description, CT + Power (see docs/wiki-reference/moz-activeskills.png).
    @ViewBuilder
    private func activeSkillRow(_ learned: Pal.LearnedSkill) -> some View {
        let skill = data.idByName[learned.name.lowercased()].flatMap { data.skillByID[$0] }
        let element = skill?.element ?? "Neutral"
        let row = HStack(alignment: .top, spacing: 10) {
            Text(learned.level.map { "Lv \($0)" } ?? "Lv ?")
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 46, height: 40)
                .background(Theme.elementColor(element), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(learned.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.elementColor(element))
                    Spacer()
                    if let ct = skill?.cooldown {
                        Text("CT \(ct)s")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let power = skill?.power {
                        Text("Power \(power)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.Stat.attack.color)
                    }
                }
                if let desc = skill?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elementColor(element).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12))

        if let skillID = data.idByName[learned.name.lowercased()] {
            NavigationLink(value: skillID) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private func statColumn(_ stat: Theme.Stat, base: Int?, range: [Int?]) -> some View {
        VStack(spacing: 4) {
            Label(base.map(String.init) ?? "?", systemImage: stat.symbol)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(stat.color)
            if range.count == 2, let low = range[0], let high = range[1] {
                Text("\(low)–\(high) @50")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func prettyWork(_ key: String) -> String {
        key.replacingOccurrences(of: #"([A-Z])"#, with: " $1", options: .regularExpression)
            .capitalized
    }

    // MARK: Item / weapon

    @ViewBuilder
    private func itemCard(_ item: Item) -> some View {
        let kind: GameData.ImageKind =
            data.weapons.contains { $0.id == item.id } ? .weapons : .items
        VStack(spacing: 10) {
            WikiImage(file: item.image, kind: kind)
                .frame(height: 120)
                .onTapGesture { zoomImage = ZoomTarget(file: item.image, kind: kind) }
            HStack(spacing: 8) {
                if !item.type.isEmpty { TagChip(text: item.type) }
                if !item.rarity.isEmpty { TagChip(text: item.rarity) }
            }
            if !item.description.isEmpty {
                Text(item.description)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)

        HStack(spacing: 14) {
            if let damage = item.damage { statPill(.attack, "\(damage)") }
            if let tier = item.techTier { statPill(.work, "Tech \(tier)") }
            if let buy = item.goldBuy { statPill(.gold, "\(buy)") }
            if let nutrition = item.nutrition { statPill(.food, "\(nutrition)") }
        }
        .frame(maxWidth: .infinity)

        if !item.craftMaterials.isEmpty {
            section("Recipe") { entityChips(item.craftMaterials) }
        }
    }

    private func statPill(_ stat: Theme.Stat, _ text: String) -> some View {
        Label(text, systemImage: stat.symbol)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(stat.color)
    }

    // MARK: Skill

    private func prettySkillType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "ex_active": "Exclusive Active"
        case "active": "Active"
        case "passive": "Passive"
        default: raw.capitalized
        }
    }

    @ViewBuilder
    private func skillCard(_ skill: Skill) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                NavigationLink(value: skill.element.lowercased()) {
                    ElementChip(element: skill.element)
                }
                TagChip(text: prettySkillType(skill.skillType))
            }
            HStack(spacing: 16) {
                if let power = skill.power { statPill(.attack, "Power \(power)") }
                if let ct = skill.cooldown { statPill(.work, "CT \(ct)s") }
            }
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)

        if !skill.exclusiveTo.isEmpty {
            section("Exclusive to") {
                FlowChipsLinked(entries: skill.exclusiveTo.map { name in
                    let entityID = data.idByName[name.lowercased()]
                    return (name, entityID, entityID.flatMap { data.palByID[$0]?.image })
                })
            }
        }

        section("Learned by") {
            if skill.learnset.isEmpty {
                Text(skill.exclusiveTo.isEmpty
                     ? "This skill is not auto-learned by any pal."
                     : "Only \(skill.exclusiveTo.joined(separator: ", ")) can use this skill; no pal auto-learns it by leveling.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LearnsetGrid(data: data, learnset: skill.learnset)
            }
        }
    }

    // MARK: Article prose

    @ViewBuilder
    private func articleSections(_ article: Article) -> some View {
        let isPal = data.palByID[article.id] != nil
        let isSkill = data.skillByID[article.id] != nil
        let sections = article.sections.filter { sec in
            if isPal && Self.palRedundantHeadings.contains(sec.heading.lowercased()) { return false }
            // skill pages render the learnset from structured data instead
            if isSkill && ["learnset", "pals"].contains(sec.heading.lowercased()) { return false }
            return true
        }
        ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
            VStack(alignment: .leading, spacing: 8) {
                if !sec.heading.isEmpty {
                    Text(sec.heading)
                        .font(sec.level == 3 ? .subheadline.weight(.bold) : .headline)
                        .foregroundStyle(sec.level == 3 ? .secondary : .primary)
                }
                if !sec.text.isEmpty {
                    SectionBody(data: data, text: sec.text, selfID: article.id)
                }
                ForEach(Array((sec.tables ?? []).enumerated()), id: \.offset) { _, table in
                    WikiTableView(data: data, table: table)
                }
                if let images = sec.images, !images.isEmpty {
                    SectionImagesPager(images: images) { file in
                        zoomImage = ZoomTarget(file: file, kind: .articles)
                    }
                }
            }
        }
    }

    private func locationCard(_ location: Location) -> some View {
        VStack(spacing: 10) {
            if !location.image.isEmpty {
                WikiImage(file: location.image, kind: .locations)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture {
                        zoomImage = ZoomTarget(file: location.image, kind: .locations)
                    }
            }
            HStack(spacing: 8) {
                if !location.type.isEmpty { TagChip(text: location.type) }
                if !location.region.isEmpty { TagChip(text: location.region) }
                if !location.level.isEmpty { TagChip(text: "Lv \(location.level)") }
            }
            if !location.inhabitants.isEmpty {
                FlowChipsLinked(entries: location.inhabitants.map { raw in
                    let entityID = data.resolveEntityName(raw)
                    return (GameData.strippedName(raw), entityID,
                            entityID.flatMap { data.palByID[$0]?.image })
                })
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entityChips(_ raws: [String]) -> some View {
        FlowChipsLinked(entries: raws.map { raw in
            let id = data.resolveEntityName(raw)
            let icon = id.flatMap { data.itemByID[$0]?.image ?? data.palByID[$0]?.image }
            return (GameData.strippedName(raw), id, icon)
        })
    }
}

/// Day/Night habitat map, like the wiki's infobox habitat widget.
struct HabitatView: View {
    let pal: Pal
    let onZoom: (String) -> Void
    @State private var night = false
    @Environment(\.showOnMap) private var showOnMap
    @Environment(\.dismiss) private var dismiss

    private var file: String? { night ? pal.habitatNight : pal.habitatDay }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Time", selection: $night) {
                Text("Day").tag(false)
                Text("Night").tag(true)
            }
            .pickerStyle(.segmented)
            if let file {
                WikiImage(file: file, kind: .maps)
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture { onZoom(file) }
            } else {
                Text(night ? "Does not spawn at night." : "Does not spawn during the day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                showOnMap(pal.name)
                dismiss()
            } label: {
                Label("Show spawn points on the Map", systemImage: "map.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.teal)
        }
    }
}

/// Wiki-style strip: how much damage this pal takes from each element.
struct ElementEffectivenessView: View {
    let elements: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Theme.allElements, id: \.self) { attacker in
                        let mult = Theme.damageMultiplier(defender: elements, attacker: attacker)
                        VStack(spacing: 6) {
                            WikiImage(file: Theme.elementIconFile(attacker), kind: .ui)
                                .frame(width: 26, height: 26)
                            Text(multText(mult))
                                .font(.caption.weight(mult == 1 ? .regular : .heavy))
                                .monospacedDigit()
                                .foregroundStyle(mult > 1 ? .red : mult < 1 ? .green : .secondary)
                        }
                        .frame(width: 42)
                        .padding(.vertical, 8)
                        .background(mult > 1 ? Color.red.opacity(0.10)
                                    : mult < 1 ? Color.green.opacity(0.10) : Color.clear)
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("How much damage this pal takes from each element.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func multText(_ m: Double) -> String {
        m == m.rounded() ? "\(Int(m))×" : String(format: "%.2g×", m)
    }
}

// MARK: - Chip components

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

/// Wrapping row of plain text chips.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { TagChip(text: $0) }
        }
    }
}

/// Wrapping row of chips that navigate when an id resolved; entries can carry
/// a small entity icon (item drop icons, pal thumbnails...).
struct FlowChipsLinked: View {
    let entries: [(label: String, id: String?, icon: String?)]

    init(entries: [(label: String, id: String?, icon: String?)]) {
        self.entries = entries
    }

    init(entries: [(label: String, id: String?)]) {
        self.entries = entries.map { ($0.label, $0.id, nil) }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                if let id = entry.id {
                    NavigationLink(value: id) {
                        chip(entry).foregroundStyle(.tint)
                    }
                } else {
                    chip(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ entry: (label: String, id: String?, icon: String?)) -> some View {
        if let icon = entry.icon {
            HStack(spacing: 5) {
                WikiImage(file: icon, kind: .items)
                    .frame(width: 16, height: 16)
                Text(entry.label)
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        } else {
            TagChip(text: entry.label)
        }
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, point) in zip(subviews, arrange(proposal: proposal, subviews: subviews).points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        var rowStart = 0

        func centerRow(upTo end: Int) {
            for i in rowStart..<end {
                points[i].y = y + (rowHeight - sizes[i].height) / 2
            }
        }

        for (i, size) in sizes.enumerated() {
            if x > 0, x + size.width > maxWidth {
                centerRow(upTo: i)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                rowStart = i
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        centerRow(upTo: sizes.count)
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

// MARK: - Technology tree

/// The Technology page gets a bespoke rendering: per-level groups of tech
/// tiles (image + points + name), with Ancient Technology highlighted purple —
/// mirroring the wiki's tech table (docs/wiki-reference/tech-table-crop.png).
struct TechnologyTreeView: View {
    let data: GameData

    private var levels: [(level: Int, techs: [TechEntry])] {
        Dictionary(grouping: data.technology, by: \.level)
            .sorted { $0.key < $1.key }
            .map { (level: $0.key, techs: $0.value.sorted { !$0.ancient && $1.ancient }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(levels, id: \.level) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Level \(group.level)")
                        .font(.headline)
                        .foregroundStyle(.teal)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                             count: 3),
                              spacing: 10) {
                        ForEach(Array(group.techs.enumerated()), id: \.offset) { _, tech in
                            techTile(tech)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func techTile(_ tech: TechEntry) -> some View {
        let accent: Color = tech.ancient ? .purple : .teal
        let tile = VStack(spacing: 4) {
            Text(tech.ancient ? "Ancient" : (tech.structure ? "Structure" : "Item"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
            WikiImage(file: tech.image, kind: .items)
                .frame(height: 52)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(tech.points)")
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent, in: Capsule())
                }
            Text(tech.name)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .top)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.35), lineWidth: 1))

        if let id = data.resolveEntityName(tech.name) {
            NavigationLink(value: id) { tile }.buttonStyle(.plain)
        } else {
            tile
        }
    }
}

// MARK: - Build catalog (Base Building page)

/// Everything buildable, grouped by structure type, generated from our own
/// item data — the wiki's per-type tables are server-side queries that don't
/// exist in the page source.
struct BuildCatalogView: View {
    let data: GameData

    private static let structureTypes = [
        "Production", "Pal", "Storage", "Infrastructure", "Lighting",
        "Foundations", "Defenses", "Furniture", "Other",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build Catalog")
                .font(.title3.bold())
            ForEach(Self.structureTypes, id: \.self) { type in
                let members = data.items
                    .filter { $0.type == type && ($0.techTier != nil || !$0.craftMaterials.isEmpty) }
                    .sorted { ($0.techTier ?? 99, $0.name) < ($1.techTier ?? 99, $1.name) }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(type) · \(members.count)")
                            .font(.headline)
                            .foregroundStyle(.teal)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                            GridItem(.flexible())],
                                  spacing: 10) {
                            ForEach(members) { item in
                                NavigationLink(value: item.id) {
                                    HStack(spacing: 8) {
                                        WikiImage(file: item.image, kind: .items)
                                            .frame(width: 34, height: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.8)
                                                .multilineTextAlignment(.leading)
                                            if let tier = item.techTier {
                                                Text("Tech \(tier)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.background.secondary,
                                                in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Wikitable rendering

/// Structured table from the wiki: bold header row, dividers, horizontal
/// scroll when wide. Cells with a link target render highlighted with the
/// linked entity's icon and navigate on tap.
struct WikiTableView: View {
    let data: GameData
    let table: Article.Table

    /// Wide or text-heavy tables don't fit a phone; each row becomes a card.
    private var useCards: Bool {
        if table.headers.count >= 4 { return true }
        let widestRow = table.rows.map(\.count).max() ?? 0
        let longestCell = table.rows.flatMap { $0.map(\.t.count) }.max() ?? 0
        return widestRow >= 4 || longestCell > 80
    }

    /// Column whose header is Icon/Image — merged into the card title.
    private var iconColumn: Int? {
        table.headers.firstIndex { ["icon", "image"].contains($0.lowercased()) }
    }

    var body: some View {
        if useCards {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible())],
                          alignment: .leading, spacing: 10) {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                        rowCard(row)
                    }
                }
                legend
            }
        } else {
            scrollingGrid
        }
    }

    /// What the stat-bubble symbols mean, for first-time readers. Only lists
    /// symbols that actually rendered as bubbles in at least one card.
    @ViewBuilder
    private var legend: some View {
        let fields = table.headers.enumerated().compactMap { (col, header) -> (String, Color, String)? in
            guard let style = Self.fieldStyle(header) else { return nil }
            let usedAsBubble = table.rows.contains { row in
                col < row.count && !row[col].t.isEmpty
                    && row[col].t.count <= 16 && !row[col].t.contains("\n")
            }
            return usedAsBubble ? (header, style.0, style.1) : nil
        }
        if !fields.isEmpty {
            FlowLayout(spacing: 10) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    HStack(spacing: 3) {
                        Image(systemName: field.2)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(field.1)
                        Text(field.0)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Field semantics -> (tint, SF symbol) for the colored value bubbles.
    private static func fieldStyle(_ header: String) -> (Color, String)? {
        let h = header.lowercased()
        if h.contains("damage") || h.contains("attack") || h.contains("power") {
            return (.red, "flame.fill")
        }
        if h.contains("durability") || h.contains("defense") { return (.blue, "shield.fill") }
        if h.contains("magazine") || h.contains("ammo") { return (.teal, "square.stack.fill") }
        if h.contains("gold") || h.contains("price") || h.contains("sell") || h.contains("buy") {
            return (.orange, "dollarsign.circle.fill")
        }
        if h.contains("workload") { return (.cyan, "hammer.fill") }
        if h.contains("tech") || h.contains("schematic") { return (.teal, "wrench.and.screwdriver.fill") }
        if h.contains("weight") { return (.gray, "scalemass.fill") }
        if h.contains("effect") || h.contains("passive") { return (.purple, "sparkles") }
        if h.contains("hp") || h.contains("health") || h.contains("nutrition") {
            return (.green, "heart.fill")
        }
        if h.contains("level") || h.contains("points") { return (.indigo, "star.fill") }
        return nil
    }

    private static func rarityColor(_ value: String) -> Color? {
        switch value.lowercased() {
        case "common": .gray
        case "uncommon": .green
        case "rare": .blue
        case "epic": .purple
        case "legendary": .orange
        default: nil
        }
    }

    @ViewBuilder
    private func rowCard(_ row: [Article.Table.Cell]) -> some View {
        let iconFile = iconColumn.flatMap { $0 < row.count ? row[$0].img : nil }
        let titleIndex = row.indices.first {
            $0 != iconColumn && !row[$0].t.isEmpty
        }
        let title = titleIndex.map { row[$0] }
        let details: [(String, Article.Table.Cell)] = row.indices.compactMap { i in
            guard i != iconColumn, i != titleIndex, i < row.count else { return nil }
            let cell = row[i]
            guard !cell.t.isEmpty || cell.img != nil else { return nil }
            return (i < table.headers.count ? table.headers[i] : "", cell)
        }
        let titleColor = title.flatMap { Self.rarityColor($0.t) }
        let titleIcon = iconFile ?? title?.img ?? title?.l.flatMap { id in
            data.palByID[id]?.image ?? data.itemByID[id]?.image
        }
        let card = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let titleIcon {
                    WikiImage(file: titleIcon, kind: .items)
                        .frame(width: 34, height: 34)
                }
                Text(title?.t ?? "")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(titleColor.map(AnyShapeStyle.init)
                                     ?? (title?.l != nil ? AnyShapeStyle(.tint)
                                         : AnyShapeStyle(.primary)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // short stats become colored bubbles; materials become icon chips;
            // long text stays as labeled prose
            FlowLayout(spacing: 5) {
                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    if isShortValue(detail), let style = Self.fieldStyle(detail.0) {
                        statBubble(detail.0, value: detail.1.t, tint: style.0, symbol: style.1)
                    }
                }
            }
            ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                if isMaterialField(detail.0) || detail.1.l != nil || detail.1.img != nil {
                    // cells referencing entities render as image chips
                    VStack(alignment: .leading, spacing: 3) {
                        if !detail.0.isEmpty {
                            Text(detail.0)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        materialChips(detail.1.t)
                    }
                } else if !(isShortValue(detail) && Self.fieldStyle(detail.0) != nil) {
                    VStack(alignment: .leading, spacing: 1) {
                        if !detail.0.isEmpty {
                            Text(detail.0)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(detail.1.t)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .background((titleColor ?? .gray).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke((titleColor ?? .gray).opacity(0.25), lineWidth: 1))

        if let link = title?.l, data.articleByID[link] != nil {
            NavigationLink(value: link) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }

    private func isMaterialField(_ header: String) -> Bool {
        let h = header.lowercased()
        return h.contains("material") || h.contains("recipe") || h.contains("ingredient")
    }

    private func isShortValue(_ detail: (String, Article.Table.Cell)) -> Bool {
        !isMaterialField(detail.0) && detail.1.t.count <= 16 && !detail.1.t.contains("\n")
    }

    private func statBubble(_ header: String, value: String, tint: Color, symbol: String) -> some View {
        StatBubble(header: header, value: value, tint: tint, symbol: symbol)
    }

    private func materialChips(_ value: String) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(value.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let entityID = data.resolveEntityName(line)
                let icon = entityID.flatMap {
                    data.itemByID[$0]?.image ?? data.palByID[$0]?.image
                }
                let chip = HStack(spacing: 4) {
                    if let icon {
                        WikiImage(file: icon, kind: .items)
                            .frame(width: 15, height: 15)
                    }
                    Text(line.trimmingCharacters(in: .whitespaces))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())

                if let entityID, data.articleByID[entityID] != nil {
                    NavigationLink(value: entityID) {
                        chip.foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                } else {
                    chip
                }
            }
        }
    }

    /// Narrow tables fit the screen width; text wraps inside the columns.
    private var scrollingGrid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
            if !table.headers.isEmpty {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 {
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func cellView(_ cell: Article.Table.Cell) -> some View {
        let icon = cell.img ?? cell.l.flatMap { id in
            data.itemByID[id]?.image ?? data.palByID[id]?.image
        }
        let content = HStack(alignment: .top, spacing: 6) {
            if let icon {
                WikiImage(file: icon, kind: .items)
                    .frame(width: 22, height: 22)
            }
            Text(cell.t)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let link = cell.l, data.articleByID[link] != nil {
            NavigationLink(value: link) {
                content.foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Colored stat capsule; tapping reveals what the symbol means.
struct StatBubble: View {
    let header: String
    let value: String
    let tint: Color
    let symbol: String
    @State private var showLabel = false

    var body: some View {
        Button {
            showLabel = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(value)
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showLabel) {
            Text(header)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .presentationCompactAdaptation(.popover)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    showLabel = false
                }
        }
    }
}

// MARK: - Section images pager

/// Swipeable horizontal pager for a section's wiki images (chest location
/// maps, gallery shots...). Tap any page to open the zoom viewer.
struct SectionImagesPager: View {
    let images: [Article.SectionImage]
    let onZoom: (String) -> Void

    var body: some View {
        TabView {
            ForEach(images, id: \.file) { image in
                VStack(spacing: 4) {
                    WikiImage(file: image.file, kind: .articles)
                        .frame(maxWidth: .infinity)
                        .frame(height: images.count > 1 ? 200 : 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture { onZoom(image.file) }
                    if !image.caption.isEmpty {
                        Text(image.caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, images.count > 1 ? 28 : 0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
        .frame(height: images.count > 1 ? 264 : 240)
    }
}

// MARK: - Learnset grid

/// Uniform "learned by" table for skill pages: pal portrait, name, unlock level.
struct LearnsetGrid: View {
    let data: GameData
    let learnset: [Skill.LearnsetEntry]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                  spacing: 8) {
            ForEach(Array(learnset.enumerated()), id: \.offset) { _, entry in
                row(entry)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: Skill.LearnsetEntry) -> some View {
        let id = data.idByName[entry.pal.lowercased()]
        let content = HStack(spacing: 8) {
            WikiImage(file: id.flatMap { data.palByID[$0]?.image } ?? "", kind: .pals)
                .frame(width: 34, height: 34)
            Text(entry.pal)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if let level = entry.level {
                Text("Lv \(level)")
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.teal, in: Capsule())
            }
        }
        .padding(6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

        if let id {
            NavigationLink(value: id) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Section body (prose + entity chip lists)

/// Renders a section's text. Runs of 2+ consecutive lines that are each an
/// entity name (the wiki's link lists, e.g. "obtained from the following
/// Pals") become wrapped icon chips; everything else stays auto-linked prose.
struct SectionBody: View {
    let data: GameData
    let text: String
    let selfID: String

    private enum Block {
        case prose(String)
        case chips([(label: String, id: String?, icon: String?)])
        case palGrid([(label: String, id: String)])
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var prose: [String] = []
        var run: [(String, String)] = []  // (label, id)

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(.prose(joined))
            }
            prose = []
        }

        func flushRun() {
            defer { run = [] }
            guard !run.isEmpty else { return }
            flushProse()
            // big all-pal lists (a region's pals) read best as an image grid
            if run.count >= 4, run.allSatisfy({ data.palByID[$0.1] != nil }) {
                result.append(.palGrid(run))
            } else {
                result.append(.chips(run.map { entry in
                    (entry.0, entry.1,
                     data.palByID[entry.1]?.image ?? data.itemByID[entry.1]?.image)
                }))
            }
        }

        let bulletChars = CharacterSet(charactersIn: "•◦\u{2003} \t")
        for line in text.components(separatedBy: "\n") {
            let candidate = line.trimmingCharacters(in: bulletChars)
            if candidate.count <= 60, !candidate.isEmpty,
               let id = data.resolveEntityName(candidate) {
                run.append((candidate, id))
            } else {
                flushRun()
                prose.append(line)
            }
        }
        flushRun()
        flushProse()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let text):
                    LinkedText(data: data, text: text, selfID: selfID)
                case .chips(let entries):
                    FlowChipsLinked(entries: entries)
                case .palGrid(let entries):
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                             count: 3),
                              spacing: 10) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            NavigationLink(value: entry.id) {
                                VStack(spacing: 4) {
                                    WikiImage(file: data.palByID[entry.id]?.image ?? "",
                                              kind: .pals)
                                        .frame(height: 70)
                                    Text(entry.label)
                                        .font(.caption2.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.7)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    (data.palByID[entry.id]?.elements.first
                                        .map(Theme.elementColor) ?? .gray).opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Prose auto-linking

/// Section text where known entity names become tappable links (first
/// occurrence of each name; word-boundary checked). Links push onto the
/// enclosing NavigationStack via the palentity:// scheme.
struct LinkedText: View {
    let data: GameData
    let text: String
    let selfID: String
    @Environment(\.libraryNavigate) private var navigate

    var body: some View {
        Text(attributed)
            .font(.callout)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "palentity", let host = url.host() else { return .discarded }
                navigate?(host)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let lower = text.lowercased()
        var linkedRanges: [Range<String.Index>] = []
        // longest names first so "Lamball Mutton" wins over "Lamball"
        for (name, id) in Self.linkIndex(for: data) where id != selfID {
            guard name.count >= 4, let range = boundaryRange(of: name, in: lower) else { continue }
            guard !linkedRanges.contains(where: { $0.overlaps(range) }) else { continue }
            linkedRanges.append(range)
            if let attrRange = Range(NSRange(range, in: text), in: result) {
                result[attrRange].link = URL(string: "palentity://\(id)")
                result[attrRange].foregroundColor = .accentColor
            }
        }
        return result
    }

    private func boundaryRange(of name: String, in lower: String) -> Range<String.Index>? {
        var searchStart = lower.startIndex
        while let range = lower.range(of: name, range: searchStart..<lower.endIndex) {
            let beforeOK = range.lowerBound == lower.startIndex
                || !lower[lower.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == lower.endIndex
                || !lower[range.upperBound].isLetter
            if beforeOK && afterOK { return range }
            searchStart = range.upperBound
        }
        return nil
    }

    /// name(lowercased) → id, longest names first. Built once per app run.
    private static var cachedIndex: [(String, String)]?
    private static func linkIndex(for data: GameData) -> [(String, String)] {
        if let cachedIndex { return cachedIndex }
        let index = data.idByName.sorted { $0.key.count > $1.key.count }
        cachedIndex = index
        return index
    }
}

/// Navigation hook LinkedText uses to push pages (set by the hosting stack).
extension EnvironmentValues {
    @Entry var libraryNavigate: ((String) -> Void)?
}

// MARK: - Zoomable full-screen image

/// Full-screen image viewer with real pinch-to-zoom, pan and double-tap,
/// backed by UIScrollView (SwiftUI gestures don't reliably do this).
struct ZoomableImageView: View {
    let file: String
    let kind: GameData.ImageKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = GameData.imageURL(file, kind: kind),
                   let image = UIImage(contentsOfFile: url.path) {
                    ZoomableScrollView(image: image)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Image unavailable", systemImage: "photo")
                }
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.frame = scrollView.bounds
        DispatchQueue.main.async {
            context.coordinator.imageView?.frame = CGRect(origin: .zero,
                                                          size: scrollView.bounds.size)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // keep the image centered while smaller than the viewport
            guard let imageView else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            imageView.center = CGPoint(x: scrollView.contentSize.width / 2 + offsetX,
                                       y: scrollView.contentSize.height / 2 + offsetY)
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.5 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 3,
                                  height: scrollView.bounds.height / 3)
                let rect = CGRect(x: point.x - size.width / 2,
                                  y: point.y - size.height / 2,
                                  width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
