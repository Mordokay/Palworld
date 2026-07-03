import SwiftUI

/// Navigation trail shown above Library pages: bubbles (with entity icons)
/// joined by arrows, wrapping onto new lines. Tapping a bubble pops back to it.
/// Height grows with the trail up to ~3 rows, then the top fades out and older
/// rows scroll away.
struct BreadcrumbView: View {
    struct Item {
        let label: String
        let icon: String?
    }

    let rootLabel: String
    let items: [Item]
    /// Pop to path index (-1 = root).
    let onTap: (Int) -> Void

    @State private var contentHeight: CGFloat = 36
    private let maxHeight: CGFloat = 118  // ~3 bubble rows

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 6) {
                    bubble(Item(label: rootLabel, icon: nil), index: -1,
                           isCurrent: items.isEmpty)
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        bubble(item, index: i, isCurrent: i == items.count - 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) {
                    contentHeight = $0
                }
                .id("trailEnd")
            }
            .frame(height: min(contentHeight, maxHeight))
            .mask(alignment: .bottom) {
                VStack(spacing: 0) {
                    if contentHeight > maxHeight {
                        LinearGradient(colors: [.clear, .black],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                    }
                    Rectangle()
                }
            }
            .onChange(of: items.count) {
                withAnimation(.snappy) { proxy.scrollTo("trailEnd", anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo("trailEnd", anchor: .bottom)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func bubble(_ item: Item, index: Int, isCurrent: Bool) -> some View {
        Button {
            onTap(index)
        } label: {
            HStack(spacing: 5) {
                if let icon = item.icon {
                    WikiImage(file: icon, kind: .items)
                        .frame(width: 16, height: 16)
                }
                Text(item.label.count > 18 ? item.label.prefix(17) + "…" : item.label)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        in: Capsule())
            .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }
}
