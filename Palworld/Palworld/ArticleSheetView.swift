import SwiftUI

/// The "learn more" sheet behind every quiz question: the full Library page,
/// with its own navigation stack (and breadcrumb trail) so cross-links work
/// inside the sheet.
struct ArticleSheetView: View {
    let data: GameData
    let articleID: String
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String]

    init(data: GameData, articleID: String, initialPath: [String] = []) {
        self.data = data
        self.articleID = articleID
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !path.isEmpty {
                BreadcrumbView(
                    rootLabel: data.articleByID[articleID]?.title ?? "Info",
                    items: path.map { data.trailItem(for: $0) }
                ) { index in
                    path = Array(path.prefix(index + 1))
                }
            }
            NavigationStack(path: $path) {
                EntityPageView(data: data, id: articleID)
                    .navigationDestination(for: String.self) { id in
                        EntityPageView(data: data, id: id)
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
        .environment(\.libraryNavigate) { id in path.append(id) }
        .fontDesign(.rounded)
    }
}
