import Combine
import SwiftUI
import UIKit

// MARK: - Map data (data/map_markers.json + data/map_spawns.json)

struct MapMarker: Codable {
    let x: Double            // 0...1, west -> east
    let y: Double            // 0...1, north -> south
    var name: String?
    var pal: String?
}

struct MapMarkerCategory: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let markers: [MapMarker]
}

/// Loaded lazily when the Map tab first appears (spawns are ~3 MB of JSON).
final class MapData {
    let categories: [MapMarkerCategory]
    /// pal display name (lowercased) -> "day"/"night" -> [[x, y], ...]
    let spawns: [String: [String: [[Double]]]]

    init?(bundle: Bundle = .main) {
        guard let root = bundle.resourceURL?.appendingPathComponent("data"),
              let markerData = try? Data(contentsOf: root.appendingPathComponent("map_markers.json")),
              let decoded = try? JSONDecoder().decode(MarkersFile.self, from: markerData)
        else { return nil }
        categories = decoded.categories
        let spawnData = try? Data(contentsOf: root.appendingPathComponent("map_spawns.json"))
        let rawSpawns = spawnData.flatMap {
            try? JSONDecoder().decode([String: [String: [[Double]]]].self, from: $0)
        } ?? [:]
        spawns = Dictionary(uniqueKeysWithValues: rawSpawns.map { ($0.key.lowercased(), $0.value) })
    }

    private struct MarkersFile: Codable {
        let categories: [MapMarkerCategory]
    }

    static func iconImage(_ name: String) -> UIImage? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("data/map/icons/\(name).png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Cross-tab request: "open the Map tab showing this pal's spawns".
@MainActor
final class MapRoute: ObservableObject {
    @Published var spawnPalName: String?
}

/// Safe-everywhere hook for pal pages (no-op outside the tab shell, e.g. in
/// debug screenshot paths that present article sheets standalone).
extension EnvironmentValues {
    @Entry var showOnMap: (String) -> Void = { _ in }
}

// MARK: - Tab view

struct PalMapView: View {
    let data: GameData
    @EnvironmentObject private var route: MapRoute
    @State private var mapData: MapData?
    @State private var missing = false
    @AppStorage("mapLayers") private var layersRaw = "fastTravel,tower,alpha"
    @AppStorage("mapVisited") private var visitedRaw = ""
    @AppStorage("mapHideVisited") private var hideVisited = false
    @State private var spawnPal: Pal?
    @State private var spawnSide = "day"
    @State private var selection: SelectedMarker?
    @State private var showFilters = false
    @State private var focus: FocusRequest?

    private var visited: Set<String> {
        Set(visitedRaw.split(separator: "|").map(String.init))
    }

    private func toggleVisited(_ key: String) {
        var set = visited
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        visitedRaw = set.joined(separator: "|")
    }

    private var enabledLayers: Set<String> {
        get { Set(layersRaw.split(separator: ",").map(String.init)) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let mapData {
                    ZStack(alignment: .bottom) {
                        TiledMapView(mapData: mapData,
                                     enabled: enabledLayers,
                                     spawns: spawnPal.flatMap { pal in
                                         mapData.spawns[pal.name.lowercased()]?
                                             .filter { $0.key == spawnSide }
                                     },
                                     visited: visited,
                                     hideVisited: hideVisited,
                                     focus: focus,
                                     palImage: { name in
                                         data.quizPals
                                             .first { $0.name.lowercased() == name }
                                             .flatMap { WikiImage.image(file: $0.image, kind: .pals) }
                                     },
                                     selection: $selection)
                            .ignoresSafeArea(edges: .bottom)
                        if let selection {
                            calloutCard(selection)
                        } else if let spawnPal {
                            spawnLegend(spawnPal)
                        }
                    }
                } else if missing {
                    ContentUnavailableView("Map data not bundled",
                                           systemImage: "map",
                                           description: Text("Run pipeline/fetch_map.py, then rebuild."))
                } else {
                    ProgressView("Loading map…")
                }
            }
            .navigationTitle("Palpagos Islands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Layers", systemImage: "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                MapFilterSheet(data: data, mapData: mapData,
                               layersRaw: $layersRaw, spawnPal: $spawnPal,
                               visited: visited, hideVisited: $hideVisited)
                    .presentationDetents([.medium, .large])
            }
            .task {
                if mapData == nil {
                    let loaded = MapData()
                    mapData = loaded
                    missing = loaded == nil
                }
                consumeRoute()
            }
            .onChange(of: route.spawnPalName) { consumeRoute() }
            .onChange(of: spawnPal?.id) {
                // picking a pal in the filter sheet also flies the camera there
                if spawnPal != nil { focusOnSpawns() }
            }
        }
    }

    private func consumeRoute() {
        guard let name = route.spawnPalName else { return }
        route.spawnPalName = nil
        spawnPal = data.quizPals.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        focusOnSpawns()
    }

    /// Zoom the camera to fit the selected pal's spawn points.
    private func focusOnSpawns() {
        guard let spawnPal, let mapData,
              let sides = mapData.spawns[spawnPal.name.lowercased()] else { return }
        // default to daytime; nocturnal pals fall back to night
        spawnSide = sides["day"]?.isEmpty == false ? "day" : "night"
        let points = sides.values.flatMap { $0 }.filter { $0.count >= 2 }
        guard let firstX = points.first?[0], let firstY = points.first?[1] else { return }
        var minX = firstX, maxX = firstX, minY = firstY, maxY = firstY
        for point in points {
            minX = min(minX, point[0]); maxX = max(maxX, point[0])
            minY = min(minY, point[1]); maxY = max(maxY, point[1])
        }
        focus = FocusRequest(rect: CGRect(x: minX, y: minY,
                                          width: maxX - minX, height: maxY - minY))
    }

    private func calloutCard(_ selected: SelectedMarker) -> some View {
        HStack(spacing: 12) {
            MapCategoryIcon(icon: selected.categoryIcon, side: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.marker.name ?? selected.categoryName)
                    .font(.headline)
                Text(selected.categoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let palName = selected.marker.pal,
               let pal = data.quizPals.first(where: { $0.name.lowercased() == palName }) {
                NavigationLink {
                    ArticleSheetView(data: data, articleID: pal.id)
                } label: {
                    HStack(spacing: 6) {
                        WikiImage(file: pal.image, kind: .pals)
                            .frame(width: 30, height: 30)
                        Image(systemName: "book.fill")
                            .font(.caption)
                    }
                }
            }
            // jump the camera back to this marker
            Button {
                focus = FocusRequest(rect: CGRect(x: selected.marker.x - 0.02,
                                                  y: selected.marker.y - 0.02,
                                                  width: 0.04, height: 0.04))
            } label: {
                Image(systemName: "location.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.teal)
            }
            .buttonStyle(.borderless)
            // 100% completion: mark this POI as seen
            Button {
                toggleVisited(selected.key)
            } label: {
                Image(systemName: visited.contains(selected.key)
                      ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(visited.contains(selected.key) ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            Button {
                selection = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func spawnLegend(_ pal: Pal) -> some View {
        let sides = mapData?.spawns[pal.name.lowercased()] ?? [:]
        let hasDay = sides["day"]?.isEmpty == false
        let hasNight = sides["night"]?.isEmpty == false
        return HStack(spacing: 10) {
            WikiImage(file: pal.image, kind: .pals)
                .frame(width: 30, height: 30)
            Text("\(pal.name) spawns")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if hasDay && hasNight {
                // one side at a time keeps the dots unambiguous
                sideButton("day", symbol: "sun.max.fill", tint: .orange)
                sideButton("night", symbol: "moon.stars.fill", tint: .indigo)
            } else {
                Label(hasNight ? "night only" : "day only",
                      systemImage: hasNight ? "moon.stars.fill" : "sun.max.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasNight ? .indigo : .orange)
            }
            Button {
                spawnPal = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding()
    }

    private func sideButton(_ side: String, symbol: String, tint: Color) -> some View {
        Button {
            spawnSide = side
        } label: {
            Label(side, systemImage: symbol)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(spawnSide == side ? tint.opacity(0.25) : .clear,
                            in: Capsule())
                .overlay(Capsule().stroke(
                    spawnSide == side ? tint : .secondary.opacity(0.3), lineWidth: 1))
                .foregroundStyle(spawnSide == side ? tint : .secondary)
        }
        .buttonStyle(.borderless)
    }
}

/// Category icon with SF-symbol fallbacks for layers that use pal artwork
/// as their map markers (alphas, predators).
struct MapCategoryIcon: View {
    let icon: String
    let side: CGFloat

    var body: some View {
        if let image = MapData.iconImage(icon) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        } else {
            Image(systemName: icon == "alpha" ? "crown.fill"
                  : icon == "predator" ? "exclamationmark.triangle.fill" : "mappin")
                .font(.system(size: side * 0.7))
                .foregroundStyle(icon == "predator" ? .red : .yellow)
                .frame(width: side, height: side)
        }
    }
}

// MARK: - Filter sheet (the palworld.gg-style layer list)

struct MapFilterSheet: View {
    let data: GameData
    let mapData: MapData?
    @Binding var layersRaw: String
    @Binding var spawnPal: Pal?
    let visited: Set<String>
    @Binding var hideVisited: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var palQuery = ""

    private var enabled: Set<String> {
        Set(layersRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $hideVisited) {
                        Label("Hide visited", systemImage: "eye.slash")
                            .font(.subheadline.weight(.semibold))
                    }
                } footer: {
                    Text("Mark points as visited from their map callout — collected effigies, opened chests…")
                }
                Section("Layers") {
                    ForEach(mapData?.categories ?? []) { category in
                        Button {
                            var set = enabled
                            if set.contains(category.id) { set.remove(category.id) }
                            else { set.insert(category.id) }
                            layersRaw = set.sorted().joined(separator: ",")
                        } label: {
                            HStack(spacing: 12) {
                                MapCategoryIcon(icon: category.icon, side: 28)
                                Text(category.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                let seen = category.markers.filter {
                                    visited.contains("\(category.id):\($0.x):\($0.y)")
                                }.count
                                Text(seen > 0 ? "\(seen)/\(category.markers.count)"
                                              : "\(category.markers.count)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(seen == category.markers.count && seen > 0
                                                     ? .green : .secondary)
                                Image(systemName: enabled.contains(category.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(enabled.contains(category.id)
                                                     ? .green : .secondary)
                            }
                        }
                    }
                }
                Section("Pal spawn areas") {
                    if let spawnPal {
                        HStack {
                            WikiImage(file: spawnPal.image, kind: .pals)
                                .frame(width: 28, height: 28)
                            Text(spawnPal.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Clear") { self.spawnPal = nil }
                                .font(.caption.weight(.semibold))
                        }
                    }
                    TextField("Search a pal…", text: $palQuery)
                    if !palQuery.isEmpty {
                        ForEach(palMatches.prefix(8)) { pal in
                            Button {
                                spawnPal = pal
                                palQuery = ""
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    WikiImage(file: pal.image, kind: .pals)
                                        .frame(width: 28, height: 28)
                                    Text(pal.name)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Map layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var palMatches: [Pal] {
        let q = palQuery.lowercased()
        return data.quizPals.filter {
            $0.name.lowercased().contains(q)
                && (mapData?.spawns[$0.name.lowercased()] != nil)
        }
    }
}

// MARK: - The tiled map (UIKit core)

/// One-shot "move the camera" command from SwiftUI to the scroll view.
struct FocusRequest: Equatable {
    let rect: CGRect     // normalized 0...1 map space
    let id = UUID()
}

struct SelectedMarker {
    let marker: MapMarker
    let categoryID: String
    let categoryName: String
    let categoryIcon: String

    /// Stable across data refreshes: category + rounded coordinates.
    var key: String { "\(categoryID):\(marker.x):\(marker.y)" }
}

struct TiledMapView: UIViewRepresentable {
    let mapData: MapData
    let enabled: Set<String>
    let spawns: [String: [[Double]]]?
    let visited: Set<String>
    let hideVisited: Bool
    let focus: FocusRequest?
    let palImage: (String) -> UIImage?
    @Binding var selection: SelectedMarker?

    final class Coordinator { var lastFocusID: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MapContainerView {
        let view = MapContainerView(mapData: mapData)
        view.overlay.palImageProvider = palImage
        view.onSelect = { selection = $0 }
        return view
    }

    func updateUIView(_ view: MapContainerView, context: Context) {
        view.overlay.enabled = enabled
        view.overlay.spawns = spawns
        view.overlay.visited = visited
        view.overlay.hideVisited = hideVisited
        view.overlay.setNeedsDisplay()
        if let focus, focus.id != context.coordinator.lastFocusID {
            context.coordinator.lastFocusID = focus.id
            view.focus(onNormalized: focus.rect, animated: true)
        }
    }
}

/// UIScrollView with a CATiledLayer map (data/map/tiles pyramid, z0-6) and a
/// screen-space marker overlay pinned above it. The overlay must NOT live in
/// the zooming content view: a 16,384px raster layer is unbackable, so it
/// stays viewport-sized and converts coordinates per frame — which also
/// keeps icons a constant on-screen size.
final class MapContainerView: UIView, UIScrollViewDelegate {
    static let worldSize: CGFloat = 16384   // 64 tiles * 256 at z6

    let scrollView = UIScrollView()
    let overlay: MarkerOverlayView
    private let content = UIView(
        frame: CGRect(x: 0, y: 0, width: worldSize, height: worldSize))
    var onSelect: ((SelectedMarker) -> Void)?

    init(mapData: MapData) {
        overlay = MarkerOverlayView(mapData: mapData)
        super.init(frame: .zero)

        let tileView = TileBackedView(frame: content.bounds)
        content.addSubview(tileView)
        scrollView.addSubview(content)
        scrollView.contentSize = content.bounds.size
        scrollView.delegate = self
        scrollView.maximumZoomScale = 2
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        // no bounce anywhere: rubber-banding past an edge (and the spring
        // back) is system-animated and desyncs the marker overlay — the map
        // simply never leaves the screen edges
        scrollView.bouncesZoom = false
        scrollView.bounces = false
        scrollView.backgroundColor = UIColor(red: 0.05, green: 0.12, blue: 0.2, alpha: 1)
        addSubview(scrollView)

        overlay.isUserInteractionEnabled = false
        overlay.positionProvider = { [weak self] in
            self?.presentedState() ?? (.zero, 1, .zero)
        }
        addSubview(overlay)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        scrollView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Redraw the overlay from the PRESENTATION layer every frame: during the
    // animated zoom-bounce the scroll view reports final values immediately,
    // so drawing from the model layer made markers jump ahead of the map.
    private var displayLink: CADisplayLink?
    private var lastState: (CGPoint, CGFloat, CGPoint) = (.zero, 0, .zero)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if window != nil {
            let link = CADisplayLink(target: self, selector: #selector(frameTick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func frameTick() {
        let state = presentedState()
        if state.0 != lastState.0 || state.1 != lastState.1 || state.2 != lastState.2 {
            lastState = state
            overlay.setNeedsDisplay()
        }
    }

    /// (contentOffset, zoom, contentOrigin) for the FRAME BEING BUILT.
    /// Model values, deliberately: every camera change is now either
    /// gesture-driven or set by our own animation, so the model is committed
    /// in the same transaction as the map layer. (Presentation-layer reads —
    /// the previous approach — lag one frame behind during drags, which
    /// showed as elastic marker movement.)
    func presentedState() -> (CGPoint, CGFloat, CGPoint) {
        (scrollView.contentOffset, scrollView.zoomScale, content.frame.origin)
    }

    /// Center the camera on a normalized-map-space rect (padded, clamped).
    /// Animated by our own display link setting MODEL values every frame, so
    /// the marker overlay tracks with zero drift.
    func focus(onNormalized rect: CGRect, animated: Bool) {
        let world = Self.worldSize
        var target = CGRect(x: rect.minX * world, y: rect.minY * world,
                            width: rect.width * world, height: rect.height * world)
        // pad, and never zoom in tighter than ~900 world units across
        target = target.insetBy(dx: -target.width * 0.25, dy: -target.height * 0.25)
        let minSide: CGFloat = 900
        if target.width < minSide || target.height < minSide {
            let grow = max(minSide - target.width, minSide - target.height) / 2
            target = target.insetBy(dx: -max(0, grow), dy: -max(0, grow))
        }
        let zoom = min(max(min(bounds.width / target.width,
                               bounds.height / target.height),
                           scrollView.minimumZoomScale),
                       scrollView.maximumZoomScale)
        let center = CGPoint(x: target.midX, y: target.midY)
        var offset = CGPoint(x: center.x * zoom - bounds.width / 2,
                             y: center.y * zoom - bounds.height / 2)
        offset.x = max(0, min(offset.x, world * zoom - bounds.width))
        offset.y = max(0, min(offset.y, world * zoom - bounds.height))
        if animated {
            animateCamera(toZoom: zoom, offset: offset)
        } else {
            scrollView.zoomScale = zoom
            scrollView.contentOffset = offset
        }
    }

    // MARK: self-driven camera animation (model values only)

    private var cameraLink: CADisplayLink?
    private var cameraStart: (zoom: CGFloat, offset: CGPoint) = (1, .zero)
    private var cameraEnd: (zoom: CGFloat, offset: CGPoint) = (1, .zero)
    private var cameraStartTime: CFTimeInterval = 0
    private let cameraDuration: CFTimeInterval = 0.6

    private func animateCamera(toZoom zoom: CGFloat, offset: CGPoint) {
        cameraLink?.invalidate()
        cameraStart = (scrollView.zoomScale, scrollView.contentOffset)
        cameraEnd = (zoom, offset)
        cameraStartTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(cameraTick))
        link.add(to: .main, forMode: .common)
        cameraLink = link
    }

    @objc private func cameraTick() {
        let raw = (CACurrentMediaTime() - cameraStartTime) / cameraDuration
        let t = min(1, max(0, raw))
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2   // easeInOut
        let e = CGFloat(eased)
        scrollView.zoomScale = cameraStart.zoom + (cameraEnd.zoom - cameraStart.zoom) * e
        scrollView.contentOffset = CGPoint(
            x: cameraStart.offset.x + (cameraEnd.offset.x - cameraStart.offset.x) * e,
            y: cameraStart.offset.y + (cameraEnd.offset.y - cameraStart.offset.y) * e)
        if t >= 1 {
            cameraLink?.invalidate()
            cameraLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        overlay.frame = bounds
        guard bounds.width > 0 else { return }
        let fit = max(bounds.width, bounds.height) / Self.worldSize
        if scrollView.minimumZoomScale != fit {
            let firstLayout = scrollView.zoomScale == 1 || scrollView.zoomScale < fit
            scrollView.minimumZoomScale = fit
            if firstLayout {
                scrollView.zoomScale = fit
                scrollView.contentOffset = CGPoint(
                    x: (scrollView.contentSize.width - bounds.width) / 2,
                    y: (scrollView.contentSize.height - bounds.height) / 2)
            }
        }
        overlay.setNeedsDisplay()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { overlay.setNeedsDisplay() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { overlay.setNeedsDisplay() }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: content)
        let worldPoint = CGPoint(x: point.x / Self.worldSize * MapContainerView.worldSize,
                                 y: point.y / Self.worldSize * MapContainerView.worldSize)
        if let hit = overlay.marker(nearContent: worldPoint,
                                    tolerance: 22 / scrollView.zoomScale) {
            onSelect?(hit)
        }
    }
}

/// CATiledLayer-backed view reading the bundled tile pyramid.
final class TileBackedView: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tiled = layer as! CATiledLayer
        tiled.tileSize = CGSize(width: 512, height: 512)
        tiled.levelsOfDetail = 7
        tiled.levelsOfDetailBias = 0
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let root = Bundle.main.resourceURL?.appendingPathComponent("data/map/tiles")
        else { return }
        // zoom level from the context scale: scale 1 = z6 (full res)
        let scale = ctx.ctm.a / UIScreen.main.scale
        let z = max(0, min(6, 6 + Int(round(log2(scale)))))
        let tileWorld = MapContainerView.worldSize / CGFloat(1 << z)
        let x0 = max(0, Int(rect.minX / tileWorld))
        let x1 = min((1 << z) - 1, Int(rect.maxX / tileWorld))
        let y0 = max(0, Int(rect.minY / tileWorld))
        let y1 = min((1 << z) - 1, Int(rect.maxY / tileWorld))
        guard x0 <= x1, y0 <= y1 else { return }
        for x in x0...x1 {
            for y in y0...y1 {
                let url = root.appendingPathComponent("\(z)/\(x)/\(y).png")
                guard let image = UIImage(contentsOfFile: url.path) else { continue }
                image.draw(in: CGRect(x: CGFloat(x) * tileWorld,
                                      y: CGFloat(y) * tileWorld,
                                      width: tileWorld, height: tileWorld))
            }
        }
    }
}

/// Screen-space marker layer: converts normalized coordinates through the
/// scroll view's offset/zoom every redraw, so icons stay a constant size.
final class MarkerOverlayView: UIView {
    private let mapData: MapData
    var enabled: Set<String> = []
    var spawns: [String: [[Double]]]?
    var visited: Set<String> = []
    var hideVisited = false
    /// Supplies (contentOffset, zoom, contentOrigin) at draw time — read
    /// from presentation layers so bounce animations track perfectly.
    var positionProvider: (() -> (CGPoint, CGFloat, CGPoint))?
    /// Alpha/predator markers draw the pal's own artwork.
    var palImageProvider: ((String) -> UIImage?)?

    private var iconCache: [String: UIImage] = [:]
    private var palThumbCache: [String: UIImage] = [:]

    private func palThumb(_ name: String) -> UIImage? {
        if let cached = palThumbCache[name] { return cached }
        guard let full = palImageProvider?(name) else { return nil }
        let side: CGFloat = 52
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            .image { _ in
                full.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
        palThumbCache[name] = thumb
        return thumb
    }

    init(mapData: MapData) {
        self.mapData = mapData
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    private func icon(_ name: String) -> UIImage? {
        if let cached = iconCache[name] { return cached }
        let image = MapData.iconImage(name)
        iconCache[name] = image
        return image
    }

    private var tintedCache: [String: UIImage] = [:]

    /// Green-washed variant for visited POIs: a partial sourceAtop overlay
    /// clipped to the icon's own pixels — original colors and linework stay
    /// visible underneath. (NB: must fill via the CGContext; the renderer's
    /// fill() convenience resets the blend mode and paints a solid square.)
    private func tintedIcon(_ name: String) -> UIImage? {
        if let cached = tintedCache[name] { return cached }
        guard let base = icon(name) else { return nil }
        let rect = CGRect(origin: .zero, size: base.size)
        let tinted = UIGraphicsImageRenderer(size: base.size).image { ctx in
            base.draw(in: rect)
            ctx.cgContext.setBlendMode(.sourceAtop)
            ctx.cgContext.setFillColor(
                UIColor.systemGreen.withAlphaComponent(0.65).cgColor)
            ctx.cgContext.fill(rect)
        }
        tintedCache[name] = tinted
        return tinted
    }

    override func draw(_ rect: CGRect) {
        guard let (offset, zoom, origin) = positionProvider?() else { return }
        let world = MapContainerView.worldSize
        let iconSide: CGFloat = 26
        let dotSide: CGFloat = 6
        // zoomed out, dense collectible layers render as dots, not icons
        let dotsOnly = zoom < 0.09
        let visible = bounds.insetBy(dx: -iconSide, dy: -iconSide)

        func screenPoint(_ nx: Double, _ ny: Double) -> CGPoint? {
            let p = CGPoint(x: CGFloat(nx) * world * zoom + origin.x - offset.x,
                            y: CGFloat(ny) * world * zoom + origin.y - offset.y)
            return visible.contains(p) ? p : nil
        }

        for category in mapData.categories where enabled.contains(category.id) {
            let dense = category.markers.count > 300
            let image = icon(category.icon)
            let ring: UIColor? = category.id == "alpha" ? .systemYellow
                : category.id == "predator" ? .systemRed : nil
            for marker in category.markers {
                guard let p = screenPoint(marker.x, marker.y) else { continue }
                let seen = visited.contains("\(category.id):\(marker.x):\(marker.y)")
                if seen && hideVisited { continue }
                if dense && dotsOnly {
                    (seen ? UIColor.systemGreen : UIColor.systemYellow).setFill()
                    UIBezierPath(ovalIn: CGRect(x: p.x - dotSide / 2, y: p.y - dotSide / 2,
                                                width: dotSide, height: dotSide)).fill()
                } else if let ring, let palName = marker.pal,
                          let thumb = palThumb(palName) {
                    // pal artwork in a circle: white outer border for
                    // contrast, inner ring = gold alpha / red predator,
                    // green when marked visited
                    let box = CGRect(x: p.x - iconSide / 2, y: p.y - iconSide / 2,
                                     width: iconSide, height: iconSide)
                    UIColor.white.setFill()
                    UIBezierPath(ovalIn: box.insetBy(dx: -4, dy: -4)).fill()
                    (seen ? UIColor.systemGreen : ring).setFill()
                    UIBezierPath(ovalIn: box.insetBy(dx: -2.5, dy: -2.5)).fill()
                    UIColor(white: 0.12, alpha: 1).setFill()
                    UIBezierPath(ovalIn: box).fill()
                    if let ctx = UIGraphicsGetCurrentContext() {
                        ctx.saveGState()
                        UIBezierPath(ovalIn: box).addClip()
                        thumb.draw(in: box.insetBy(dx: 1, dy: 1))
                        ctx.restoreGState()
                    }
                } else if let baseImage = seen ? tintedIcon(category.icon) : image {
                    baseImage.draw(in: CGRect(x: p.x - iconSide / 2,
                                              y: p.y - iconSide / 2,
                                              width: iconSide, height: iconSide))
                }
            }
        }

        if let spawns {
            let spawnSide: CGFloat = 8
            for (side, color) in [("day", UIColor.systemOrange),
                                  ("night", UIColor.systemIndigo)] {
                guard let points = spawns[side] else { continue }
                for point in points where point.count >= 2 {
                    guard let p = screenPoint(point[0], point[1]) else { continue }
                    let dot = CGRect(x: p.x - spawnSide / 2, y: p.y - spawnSide / 2,
                                     width: spawnSide, height: spawnSide)
                    color.withAlphaComponent(0.85).setFill()
                    let path = UIBezierPath(ovalIn: dot)
                    path.fill()
                    UIColor.white.withAlphaComponent(0.9).setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }
    }

    /// Hit-test in CONTENT coordinates (the 16,384-unit space).
    func marker(nearContent point: CGPoint, tolerance: CGFloat) -> SelectedMarker? {
        let world = MapContainerView.worldSize
        var best: (SelectedMarker, CGFloat)?
        for category in mapData.categories where enabled.contains(category.id) {
            for marker in category.markers {
                if hideVisited,
                   visited.contains("\(category.id):\(marker.x):\(marker.y)") {
                    continue
                }
                let dx = CGFloat(marker.x) * world - point.x
                let dy = CGFloat(marker.y) * world - point.y
                let dist = hypot(dx, dy)
                if dist < tolerance && (best == nil || dist < best!.1) {
                    best = (SelectedMarker(marker: marker, categoryID: category.id,
                                           categoryName: category.name,
                                           categoryIcon: category.icon), dist)
                }
            }
        }
        return best?.0
    }
}
