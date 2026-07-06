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
    @State private var spawnPal: Pal?
    @State private var selection: SelectedMarker?
    @State private var showFilters = false

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
                                     spawns: spawnPal.flatMap { mapData.spawns[$0.name.lowercased()] },
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
                               layersRaw: $layersRaw, spawnPal: $spawnPal)
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
        }
    }

    private func consumeRoute() {
        guard let name = route.spawnPalName else { return }
        route.spawnPalName = nil
        spawnPal = data.quizPals.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
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
        HStack(spacing: 10) {
            WikiImage(file: pal.image, kind: .pals)
                .frame(width: 30, height: 30)
            Text("\(pal.name) spawns")
                .font(.subheadline.weight(.semibold))
            Label("day", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Label("night", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.indigo)
            Spacer()
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
    @Environment(\.dismiss) private var dismiss
    @State private var palQuery = ""

    private var enabled: Set<String> {
        Set(layersRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            List {
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
                                Text("\(category.markers.count)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
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

struct SelectedMarker {
    let marker: MapMarker
    let categoryName: String
    let categoryIcon: String
}

struct TiledMapView: UIViewRepresentable {
    let mapData: MapData
    let enabled: Set<String>
    let spawns: [String: [[Double]]]?
    let palImage: (String) -> UIImage?
    @Binding var selection: SelectedMarker?

    func makeUIView(context: Context) -> MapContainerView {
        let view = MapContainerView(mapData: mapData)
        view.overlay.palImageProvider = palImage
        view.onSelect = { selection = $0 }
        return view
    }

    func updateUIView(_ view: MapContainerView, context: Context) {
        view.overlay.enabled = enabled
        view.overlay.spawns = spawns
        view.overlay.setNeedsDisplay()
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
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = UIColor(red: 0.05, green: 0.12, blue: 0.2, alpha: 1)
        addSubview(scrollView)

        overlay.isUserInteractionEnabled = false
        overlay.positionProvider = { [weak self] in
            guard let self else { return (.zero, 1) }
            return (self.scrollView.contentOffset, self.scrollView.zoomScale)
        }
        addSubview(overlay)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        scrollView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

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
    /// Supplies (contentOffset, zoomScale) at draw time.
    var positionProvider: (() -> (CGPoint, CGFloat))?
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

    override func draw(_ rect: CGRect) {
        guard let (offset, zoom) = positionProvider?() else { return }
        let world = MapContainerView.worldSize
        let iconSide: CGFloat = 26
        let dotSide: CGFloat = 6
        // zoomed out, dense collectible layers render as dots, not icons
        let dotsOnly = zoom < 0.09
        let visible = bounds.insetBy(dx: -iconSide, dy: -iconSide)

        func screenPoint(_ nx: Double, _ ny: Double) -> CGPoint? {
            let p = CGPoint(x: CGFloat(nx) * world * zoom - offset.x,
                            y: CGFloat(ny) * world * zoom - offset.y)
            return visible.contains(p) ? p : nil
        }

        for category in mapData.categories where enabled.contains(category.id) {
            let dense = category.markers.count > 300
            let image = icon(category.icon)
            let ring: UIColor? = category.id == "alpha" ? .systemYellow
                : category.id == "predator" ? .systemRed : nil
            for marker in category.markers {
                guard let p = screenPoint(marker.x, marker.y) else { continue }
                if dense && dotsOnly {
                    UIColor.systemYellow.setFill()
                    UIBezierPath(ovalIn: CGRect(x: p.x - dotSide / 2, y: p.y - dotSide / 2,
                                                width: dotSide, height: dotSide)).fill()
                } else if let ring, let palName = marker.pal,
                          let thumb = palThumb(palName) {
                    // pal artwork in a circle: white outer border for
                    // contrast on the dark map, colored inner ring for
                    // meaning (gold = alpha, red = predator's aura)
                    let box = CGRect(x: p.x - iconSide / 2, y: p.y - iconSide / 2,
                                     width: iconSide, height: iconSide)
                    UIColor.white.setFill()
                    UIBezierPath(ovalIn: box.insetBy(dx: -4, dy: -4)).fill()
                    ring.setFill()
                    UIBezierPath(ovalIn: box.insetBy(dx: -2.5, dy: -2.5)).fill()
                    UIColor(white: 0.12, alpha: 1).setFill()
                    UIBezierPath(ovalIn: box).fill()
                    if let ctx = UIGraphicsGetCurrentContext() {
                        ctx.saveGState()
                        UIBezierPath(ovalIn: box).addClip()
                        thumb.draw(in: box.insetBy(dx: 1, dy: 1))
                        ctx.restoreGState()
                    }
                } else if let image {
                    image.draw(in: CGRect(x: p.x - iconSide / 2, y: p.y - iconSide / 2,
                                          width: iconSide, height: iconSide))
                }
            }
        }

        if let spawns {
            for (side, color) in [("day", UIColor.systemOrange),
                                  ("night", UIColor.systemIndigo)] {
                guard let points = spawns[side] else { continue }
                color.withAlphaComponent(0.75).setFill()
                for point in points where point.count >= 2 {
                    guard let p = screenPoint(point[0], point[1]) else { continue }
                    UIBezierPath(ovalIn: CGRect(x: p.x - dotSide / 2, y: p.y - dotSide / 2,
                                                width: dotSide, height: dotSide)).fill()
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
                let dx = CGFloat(marker.x) * world - point.x
                let dy = CGFloat(marker.y) * world - point.y
                let dist = hypot(dx, dy)
                if dist < tolerance && (best == nil || dist < best!.1) {
                    best = (SelectedMarker(marker: marker, categoryName: category.name,
                                           categoryIcon: category.icon), dist)
                }
            }
        }
        return best?.0
    }
}
