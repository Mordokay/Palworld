import SwiftUI

/// Custom Library page for the nine elements: icon header, strengths and
/// weaknesses, this element's skills, and image grids of its pals (regular +
/// subspecies) — replacing the wiki's raw link lists.
struct ElementPageView: View {
    let data: GameData
    let element: String

    private var color: Color { Theme.elementColor(element) }

    private var strongAgainst: [String] {
        Theme.allElements.filter {
            Theme.damageMultiplier(defender: [$0], attacker: element) > 1
        }
    }

    private var weakAgainst: [String] {
        Theme.allElements.filter {
            Theme.damageMultiplier(defender: [$0], attacker: element) < 1
        }
    }

    private var members: (regular: [Pal], subspecies: [Pal]) {
        let all = data.pals
            .filter { $0.elements.contains { $0.caseInsensitiveCompare(element) == .orderedSame } }
            .sorted { ($0.number.isEmpty ? "999" : $0.number) < ($1.number.isEmpty ? "999" : $1.number) }
        let subs = all.filter { pal in pal.categories.contains { $0.hasSuffix("Subspecies") } }
        return (all.filter { !subs.contains($0) }, subs)
    }

    private var skills: [Skill] {
        data.skills
            .filter { $0.element.caseInsensitiveCompare(element) == .orderedSame }
            .sorted { ($0.power ?? 0) < ($1.power ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                WikiImage(file: Theme.elementIconFile(element), kind: .ui)
                    .frame(width: 64, height: 64)
                Text(element)
                    .font(.largeTitle.bold())
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 24) {
                matchupColumn("Strong against", elements: strongAgainst, symbol: "arrow.up.circle.fill", tint: .green)
                matchupColumn("Weak against", elements: weakAgainst, symbol: "arrow.down.circle.fill", tint: .red)
            }
            .frame(maxWidth: .infinity)

            // prose from the article (intro + generic properties), lists removed
            if let article = data.articleByID[element.lowercased()] {
                ForEach(Array(article.sections.enumerated()), id: \.offset) { _, sec in
                    if !sectionIsPalList(sec), !sec.text.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !sec.heading.isEmpty {
                                Text(sec.heading).font(.headline)
                            }
                            LinkedText(data: data, text: sec.text, selfID: article.id)
                        }
                    }
                }
            }

            if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(element) Skills").font(.headline)
                    FlowChipsLinked(entries: skills.map {
                        ("\($0.name)\($0.power.map { " · \($0)" } ?? "")", $0.id, nil)
                    })
                }
            }

            palGrid("\(element) Pals", pals: members.regular)
            palGrid("Subspecies", pals: members.subspecies)
        }
    }

    private func sectionIsPalList(_ sec: Article.Section) -> Bool {
        let h = sec.heading.lowercased()
        return h.contains("pals") || h.contains("subspecies") || h.contains("skills")
    }

    private func matchupColumn(_ title: String, elements: [String],
                               symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            if elements.isEmpty {
                Text("None").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(elements, id: \.self) { el in
                NavigationLink(value: el.lowercased()) {
                    ElementChip(element: el)
                }
            }
        }
    }

    @ViewBuilder
    private func palGrid(_ title: String, pals: [Pal]) -> some View {
        if !pals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                          spacing: 10) {
                    ForEach(pals) { pal in
                        NavigationLink(value: pal.id) {
                            VStack(spacing: 4) {
                                WikiImage(file: pal.image, kind: .pals)
                                    .frame(height: 70)
                                Text(pal.name)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Interactive breeding calculator: pick two parents, see the child computed
/// the same way the game does (closest breed power to the parents' average).
struct BreedingCalculatorView: View {
    let data: GameData
    @State private var parentA: Pal?
    @State private var parentB: Pal?
    @State private var picking: Int?

    private var breedable: [Pal] {
        data.pals.filter { $0.breedPower != nil }.sorted { $0.name < $1.name }
    }

    private var child: Pal? {
        guard let a = parentA?.breedPower, let b = parentB?.breedPower else { return nil }
        // same parents -> same pal; otherwise closest breed power to the average
        if parentA?.id == parentB?.id { return parentA }
        let target = Double(a + b) / 2
        return breedable.min { lhs, rhs in
            let dl = abs(Double(lhs.breedPower!) - target)
            let dr = abs(Double(rhs.breedPower!) - target)
            return dl != dr ? dl < dr
                : (lhs.number.isEmpty ? "999" : lhs.number) < (rhs.number.isEmpty ? "999" : rhs.number)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Breeding Calculator")
                .font(.title3.bold())
            HStack(spacing: 10) {
                parentSlot(parentA, label: "Parent 1") { picking = 0 }
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                parentSlot(parentB, label: "Parent 2") { picking = 1 }
            }
            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
            if let child {
                NavigationLink(value: child.id) {
                    VStack(spacing: 6) {
                        WikiImage(file: child.image, kind: .pals)
                            .frame(height: 110)
                        Text(child.name).font(.headline)
                        HStack {
                            ForEach(child.elements, id: \.self) { ElementChip(element: $0) }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            } else {
                Text("Choose two parents to see their child.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Child = pal whose breed power is closest to the parents' average. Special unique combinations in the game may differ.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .sheet(item: $picking) { slot in
            PalPickerSheet(pals: breedable) { pal in
                if slot == 0 { parentA = pal } else { parentB = pal }
            }
        }
    }

    private func parentSlot(_ pal: Pal?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let pal {
                    WikiImage(file: pal.image, kind: .pals)
                        .frame(height: 72)
                    Text(pal.name)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                } else {
                    Image(systemName: "plus.circle.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(height: 72)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct PalPickerSheet: View {
    let pals: [Pal]
    let onPick: (Pal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Pal] {
        query.isEmpty ? pals : pals.filter { $0.name.lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { pal in
                Button {
                    onPick(pal)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        WikiImage(file: pal.image, kind: .pals)
                            .frame(width: 40, height: 40)
                        Text(pal.name)
                        Spacer()
                        ForEach(pal.elements, id: \.self) { element in
                            WikiImage(file: Theme.elementIconFile(element), kind: .ui)
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Pal name")
            .navigationTitle("Choose a parent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
