import SwiftUI

/// Library tab root: browse by kind, search everything, navigate by entity id.
/// The path is plain Strings: entity/article ids, or "section:<raw>" for the
/// kind lists — readable, so the breadcrumb trail can render and pop it.
struct LibraryView: View {
    let data: GameData
    @State private var path: [String] = []
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if !path.isEmpty {
                BreadcrumbView(rootLabel: "Library",
                               items: path.map { data.trailItem(for: $0) }) { index in
                    path = Array(path.prefix(index + 1))
                }
            }
            NavigationStack(path: $path) {
                Group {
                    if query.isEmpty {
                        browseList
                    } else {
                        searchResults
                    }
                }
                .navigationTitle("Library")
                .searchable(text: $query, prompt: "Pals, items, skills, guides…")
                .navigationDestination(for: String.self) { id in
                    if let section = LibrarySection.fromRoute(id) {
                        section.listView(data: data)
                    } else {
                        EntityPageView(data: data, id: id)
                    }
                }
            }
        }
        .environment(\.libraryNavigate) { id in path.append(id) }
    }

    private var browseList: some View {
        List {
            Section {
                ForEach(LibrarySection.allCases) { section in
                    NavigationLink(value: section.route) {
                        Label {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text("\(section.count(data))")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: section.symbol)
                                .foregroundStyle(section.color)
                        }
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        List {
            let q = query.lowercased()
            let hits = data.articles
                .filter { $0.title.lowercased().contains(q) }
                .sorted {
                    // prefix matches first, then shorter titles
                    let ap = $0.title.lowercased().hasPrefix(q), bp = $1.title.lowercased().hasPrefix(q)
                    return ap != bp ? ap : $0.title.count < $1.title.count
                }
                .prefix(60)
            ForEach(Array(hits)) { article in
                NavigationLink(value: article.id) {
                    HStack(spacing: 12) {
                        searchThumb(article)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title).font(.body.weight(.medium))
                            Text(article.kind.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchThumb(_ article: Article) -> some View {
        if let pal = data.palByID[article.id] {
            WikiImage(file: pal.image, kind: .pals).frame(width: 40, height: 40)
        } else if let item = data.itemByID[article.id] {
            let kind: GameData.ImageKind =
                data.weapons.contains { $0.id == item.id } ? .weapons : .items
            WikiImage(file: item.image, kind: kind).frame(width: 40, height: 40)
        } else {
            Image(systemName: "doc.text")
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sections

enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case pals, items, weapons, skills, locations, guides, updates

    var id: String { rawValue }

    /// Route string used in the Library navigation path.
    var route: String { "section:\(rawValue)" }

    static func fromRoute(_ route: String) -> LibrarySection? {
        route.hasPrefix("section:") ? LibrarySection(rawValue: String(route.dropFirst(8))) : nil
    }

    var title: String {
        switch self {
        case .guides: "Guides & World"
        case .updates: "Update History"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .pals: "pawprint.fill"
        case .items: "shippingbox.fill"
        case .weapons: "shield.lefthalf.filled"
        case .skills: "sparkles"
        case .locations: "map.fill"
        case .guides: "text.book.closed.fill"
        case .updates: "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .pals: .green
        case .items: .orange
        case .weapons: .red
        case .skills: .purple
        case .locations: .teal
        case .guides: .blue
        case .updates: .gray
        }
    }

    static func isGameVersion(_ article: Article) -> Bool {
        article.categories.contains("Game Versions")
    }

    func articleIDs(_ data: GameData) -> [String] {
        switch self {
        case .guides:
            return data.articles
                .filter { $0.kind == "article" && !Self.isGameVersion($0) }
                .map(\.id)
        case .updates:
            // newest version first (natural version-number ordering)
            return data.articles.filter(Self.isGameVersion)
                .sorted { versionKey($0.title).lexicographicallyPrecedes(versionKey($1.title)) == false }
                .map(\.id)
        default:
            return []
        }
    }

    private func versionKey(_ title: String) -> [Int] {
        title.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
    }

    func count(_ data: GameData) -> Int {
        switch self {
        case .pals: data.pals.count
        case .items: data.items.count
        case .weapons: data.weapons.count
        case .skills: data.skills.count
        case .locations: data.locations.count
        case .guides, .updates: articleIDs(data).count
        }
    }

    @ViewBuilder
    func listView(data: GameData) -> some View {
        switch self {
        case .pals: PaldexGridView(data: data)
        case .items: ItemListView(data: data, items: data.items, kind: .items, title: "Items")
        case .weapons: ItemListView(data: data, items: data.weapons, kind: .weapons, title: "Weapons")
        case .skills: SkillListView(data: data)
        case .locations: SimpleArticleList(title: "Locations",
                                           ids: data.locations.map(\.id), data: data)
        case .guides: SimpleArticleList(title: "Guides & World",
                                        ids: articleIDs(data), data: data)
        case .updates: SimpleArticleList(title: "Update History",
                                         ids: articleIDs(data), data: data, sorted: false)
        }
    }
}

// MARK: - Paldex grid

struct PaldexGridView: View {
    let data: GameData
    @State private var query = ""
    /// empty = default Paldeck-number order; otherwise keep pals that have ALL
    /// of these works and sort by the SUM of their levels in them.
    @State private var workFilters: Set<String> = []
    @State private var workDescending = true

    /// Selected keys in the canonical in-game order (stable display order).
    private var selectedKeys: [String] {
        Theme.allWorkKeys.filter { workFilters.contains($0) }
    }

    private func workTotal(_ pal: Pal) -> Int {
        workFilters.reduce(0) { $0 + (pal.workSuitability[$1] ?? 0) }
    }

    private var pals: [Pal] {
        let byNumber: (Pal, Pal) -> Bool = {
            ($0.number.isEmpty ? "999" : $0.number, $0.name)
                < ($1.number.isEmpty ? "999" : $1.number, $1.name)
        }
        var result = data.pals
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query.lowercased()) }
        }
        if !workFilters.isEmpty {
            // keep only pals that can do EVERY selected work
            result = result.filter { pal in
                workFilters.allSatisfy { (pal.workSuitability[$0] ?? 0) > 0 }
            }
            result.sort { a, b in
                let ta = workTotal(a), tb = workTotal(b)
                if ta != tb { return workDescending ? ta > tb : ta < tb }
                return byNumber(a, b)
            }
        } else {
            result.sort(by: byNumber)
        }
        return result
    }

    var body: some View {
        ScrollView {
            workBubbles
                .padding(.horizontal)
                .padding(.top, 8)
            if !workFilters.isEmpty {
                Text("\(pals.count) pal\(pals.count == 1 ? "" : "s") with \(selectedKeys.map(Theme.workLabel).joined(separator: " + ")) — tap one to see where it spawns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 10) {
                ForEach(pals) { pal in
                    NavigationLink(value: pal.id) {
                        VStack(spacing: 4) {
                            WikiImage(file: pal.image, kind: .pals)
                                .frame(height: 84)
                            Text(pal.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if workFilters.isEmpty {
                                Text(pal.number.isEmpty ? "—" : "#\(pal.number)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                workBadges(for: pal)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(
                            (pal.elements.first.map(Theme.elementColor) ?? .gray).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .navigationTitle("Paldex")
        .searchable(text: $query, prompt: "Pal name")
    }

    /// Multi-select colored work bubbles + a sort-order toggle. Tapping a
    /// bubble toggles it; several can be active at once.
    private var workBubbles: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(Theme.allWorkKeys, id: \.self) { key in
                    workBubble(key)
                }
            }
            if !workFilters.isEmpty {
                HStack {
                    Button {
                        workDescending.toggle()
                    } label: {
                        Label(workDescending ? "Highest combined" : "Lowest combined",
                              systemImage: workDescending ? "arrow.down" : "arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    Spacer()
                    Button("Clear") { workFilters.removeAll() }
                        .font(.caption.weight(.semibold))
                }
                .padding(.top, 2)
            }
        }
    }

    private func workBubble(_ key: String) -> some View {
        let active = workFilters.contains(key)
        let color = Theme.workColor(key)
        return Button {
            if active { workFilters.remove(key) } else { workFilters.insert(key) }
        } label: {
            HStack(spacing: 5) {
                WikiImage(file: Theme.workIconFile(key), kind: .ui)
                    .frame(width: 16, height: 16)
                Text(Theme.workLabel(key))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? color.opacity(0.28) : Color.primary.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(active ? color : Color.primary.opacity(0.18), lineWidth: 1.5))
            .foregroundStyle(active ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    /// Cell footer: one icon + stars row per selected work (colored to match).
    private func workBadges(for pal: Pal) -> some View {
        VStack(spacing: 1) {
            ForEach(selectedKeys, id: \.self) { key in
                HStack(spacing: 3) {
                    WikiImage(file: Theme.workIconFile(key), kind: .ui)
                        .frame(width: 12, height: 12)
                    Text(String(repeating: "★", count: pal.workSuitability[key] ?? 0))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.workColor(key))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Item / weapon list

struct ItemListView: View {
    let data: GameData
    let items: [Item]
    let kind: GameData.ImageKind
    let title: String
    @State private var query = ""
    /// 729 items is a wall of rows — types start collapsed and expand on tap.
    @State private var expanded: Set<String> = []

    private var groups: [(type: String, items: [Item])] {
        let filtered = query.isEmpty ? items
            : items.filter { $0.name.lowercased().contains(query.lowercased()) }
        return Dictionary(grouping: filtered) { $0.type.isEmpty ? "Other" : $0.type }
            .sorted { $0.key < $1.key }
            .map { (type: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.type) { group in
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(group.type) || !query.isEmpty },
                        set: { open in
                            if open { expanded.insert(group.type) }
                            else { expanded.remove(group.type) }
                        }
                    )) {
                        ForEach(group.items) { item in
                            NavigationLink(value: item.id) {
                                HStack(spacing: 12) {
                                    WikiImage(file: item.image, kind: kind)
                                        .frame(width: 36, height: 36)
                                    Text(item.name)
                                    Spacer()
                                    if !item.rarity.isEmpty && item.rarity != "Common" {
                                        Text(item.rarity)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(group.type)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Name")
    }
}

// MARK: - Skill list

struct SkillListView: View {
    let data: GameData
    @State private var query = ""

    private var groups: [(element: String, skills: [Skill])] {
        let filtered = query.isEmpty ? data.skills
            : data.skills.filter { $0.name.lowercased().contains(query.lowercased()) }
        return Dictionary(grouping: filtered) { $0.element.isEmpty ? "Other" : $0.element }
            .sorted { $0.key < $1.key }
            .map { (element: $0.key, skills: $0.value.sorted { ($0.power ?? 0) < ($1.power ?? 0) }) }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.element) { group in
                Section {
                    ForEach(group.skills) { skill in
                        NavigationLink(value: skill.id) {
                            HStack {
                                Circle()
                                    .fill(Theme.elementColor(skill.element))
                                    .frame(width: 10, height: 10)
                                Text(skill.name)
                                Spacer()
                                if let power = skill.power {
                                    Text("\(power)")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.Stat.attack.color)
                                }
                            }
                        }
                    }
                } header: {
                    Text(group.element).foregroundStyle(Theme.elementColor(group.element))
                }
            }
        }
        .navigationTitle("Skills")
        .searchable(text: $query, prompt: "Skill name")
    }
}

// MARK: - Plain article list

struct SimpleArticleList: View {
    let title: String
    let ids: [String]
    let data: GameData
    var sorted = true
    @State private var query = ""

    private var articles: [Article] {
        var all = ids.compactMap { data.articleByID[$0] }
        if sorted { all.sort { $0.title < $1.title } }
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        List(articles) { article in
            NavigationLink(article.title, value: article.id)
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Title")
    }
}
