import SwiftUI
import StorageCore

/// Leaf opened in the detail sheet.
struct LeafSelection: Identifiable {
    let node: StorageNode
    /// Location shown in the sheet ("2024 › Marzo 2024").
    let location: String
    var id: String { node.id }
}

enum ExplorerPanel: Hashable {
    case content, types, largest
}

/// Memoizes the heavy analyses of the node being shown.
final class ExplorerCache {
    private var extKey = ""
    private var extValue: [ExtensionStat] = []
    private var catKey = ""
    private var catValue: [CategoryStat] = []
    private var bigKey = ""
    private var bigValue: [LeafRef] = []

    private func key(_ n: StorageNode) -> String { "\(n.id)|\(n.size)|\(n.fileCount)" }

    func extensions(_ n: StorageNode) -> [ExtensionStat] {
        let k = key(n)
        if k != extKey { extValue = Array(Analysis.extensions(n).prefix(150)); extKey = k }
        return extValue
    }

    func categories(_ n: StorageNode) -> [CategoryStat] {
        let k = key(n)
        if k != catKey { catValue = Analysis.categories(n); catKey = k }
        return catValue
    }

    func largest(_ n: StorageNode) -> [LeafRef] {
        let k = key(n)
        if k != bigKey { bigValue = Analysis.largest(n, limit: 100); bigKey = k }
        return bigValue
    }
}

/// Scale + offset used for the zoom animation of the map.
struct ZoomTransform: Equatable {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var tx: CGFloat = 0
    var ty: CGFloat = 0
    static let identity = ZoomTransform()
}

/// WizTree-like explorer: breadcrumb, size header, block map with zoom,
/// then content / types / biggest items of the current block.
struct ExplorerView<Header: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.colorScheme) private var colorScheme
    let source: ExplorerSource
    let root: StorageNode
    @ViewBuilder var header: () -> Header

    @State private var path: [Int] = []
    @State private var panel: ExplorerPanel = .content
    @State private var zoom = ZoomTransform.identity
    @State private var mapOpacity: Double = 1
    @State private var mapSize: CGSize = .zero
    @State private var selection: LeafSelection?
    @State private var visibleCount = 80
    @State private var cache = ExplorerCache()
    @State private var pendingDelete: [StorageNode] = []
    @State private var showDeleteConfirm = false

    private var validPath: [Int] { root.validContainerPath(path) }
    private var current: StorageNode { root.node(at: validPath) ?? root }
    private var trail: [StorageNode] { root.trail(validPath) }
    private var settings: AppSettings { model.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header()
                breadcrumb
                summaryCard
                mapCard
                if settings.colorMode == .type { legend }
                M3Segmented(options: [
                    (value: ExplorerPanel.content, title: "Contenuto", icon: "square.grid.2x2"),
                    (value: ExplorerPanel.types, title: "Tipi", icon: "chart.pie"),
                    (value: ExplorerPanel.largest, title: "Più grandi", icon: "arrow.up.right")
                ], selection: $panel)
                .padding(.top, 4)
                switch panel {
                case .content: contentPanel
                case .types: typesPanel
                case .largest: largestPanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(m3.surface)
        .navigationTitle(model.title(for: source))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sensoryFeedback(.impact(weight: .light), trigger: settings.haptics ? validPath : [])
        .sheet(item: $selection) { sel in
            ItemDetailSheet(source: source, node: sel.node, location: sel.location, rootSize: root.size)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(deleteTitle, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                let nodes = pendingDelete
                Task { await model.delete(nodes, from: source) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("L'operazione non si può annullare.")
        }
        .onChange(of: validPath) { _, _ in visibleCount = 80 }
    }

    // MARK: - Header pieces

    private var breadcrumb: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    crumb(root.name, level: 0, isLast: validPath.isEmpty, icon: source == .photos ? "photo.on.rectangle" : "internaldrive")
                    ForEach(Array(trail.enumerated()), id: \.offset) { i, node in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(m3.onSurfaceVariant)
                        crumb(node.name, level: i + 1, isLast: i == trail.count - 1, icon: nil)
                            .id(i + 1)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: validPath.count) { _, n in
                withAnimation { proxy.scrollTo(n, anchor: .trailing) }
            }
        }
    }

    private func crumb(_ title: String, level: Int, isLast: Bool, icon: String?) -> some View {
        Button {
            goUp(to: level)
        } label: {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
                Text(title)
                    .font(.m3LabelLarge)
                    .lineLimit(1)
            }
            .foregroundStyle(isLast ? m3.onSecondaryContainer : m3.onSurfaceVariant)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isLast ? m3.secondaryContainer : m3.surfaceContainerHigh, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(isLast)
    }

    private var summaryCard: some View {
        let node = current
        let parent = validPath.isEmpty ? nil : root.node(at: Array(validPath.dropLast()))
        return M3Card(color: m3.surfaceContainer) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.m3TitleLarge)
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                        SizeHeadline(bytes: node.size, units: settings.units)
                    }
                    Spacer()
                    if !validPath.isEmpty {
                        TonalIconButton(icon: "arrow.up", size: 44) { goUp(to: validPath.count - 1) }
                            .accessibilityLabel("Livello superiore")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let parent {
                            InfoChip(icon: "chart.pie.fill", text: "\(Fmt.percent(node.fraction(of: parent.size))) di \(parent.name)")
                        }
                        if !validPath.isEmpty {
                            InfoChip(icon: "square.stack.3d.up.fill", text: "\(Fmt.percent(node.fraction(of: root.size))) del totale")
                        }
                        InfoChip(icon: "doc.fill", text: Fmt.plural(node.fileCount, "elemento", "elementi"))
                        if node.folderCount > 0 {
                            InfoChip(icon: "folder.fill", text: Fmt.plural(node.folderCount, source == .photos ? "gruppo" : "cartella", source == .photos ? "gruppi" : "cartelle"))
                        }
                        if node.allocated != node.size && source != .photos {
                            InfoChip(icon: "internaldrive.fill", text: "Allocati \(model.bytes(node.allocated))")
                        }
                        if let d = node.modified {
                            InfoChip(icon: "clock.fill", text: Fmt.date(d))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        let node = current
        return M3Card(color: m3.surfaceContainerHigh, padding: 6, corner: 28) {
            ZStack {
                if node.size == 0 || node.children.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 34, weight: .light))
                        Text(node.detail ?? (node.children.isEmpty ? "Vuoto" : "Nessun dato"))
                            .font(.m3TitleSmall)
                    }
                    .foregroundStyle(m3.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TreemapView(
                        node: node,
                        depth: settings.depth,
                        colorMode: settings.colorMode,
                        cushion: settings.cushion,
                        labels: settings.labels,
                        units: settings.units,
                        thumbnails: settings.thumbnails && source == .photos,
                        corner: 22
                    ) { tile in
                        open(index: tile.path[0], rect: CGRect(x: tile.rect.x, y: tile.rect.y, width: tile.rect.w, height: tile.rect.h))
                    }
                    .id(node.id)
                    .scaleEffect(x: zoom.sx, y: zoom.sy, anchor: .topLeading)
                    .offset(x: zoom.tx, y: zoom.ty)
                    .opacity(mapOpacity)
                }
            }
            .frame(height: mapHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
        }
    }

    private var mapHeight: CGFloat {
        let w = mapSize.width > 0 ? mapSize.width : 360
        return min(560, max(280, w * 1.12))
    }

    private var legend: some View {
        let cats = cache.categories(current).prefix(8)
        let colorizer = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: settings.seed)
        let total = max(1, current.size)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(cats)) { c in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(colorizer.leaf(category: c.category, ext: "", topIndex: 0, depth: 1, id: "").base)
                            .frame(width: 12, height: 12)
                        Text(c.category.label)
                            .font(.m3LabelMedium)
                            .foregroundStyle(m3.onSurface)
                        Text(Fmt.percent(Double(c.size) / Double(total), digits: 0))
                            .font(.m3LabelSmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(m3.outlineVariant, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Panels

    private var contentPanel: some View {
        let node = current
        let colorizer = TileColorizer(mode: settings.colorMode, dark: colorScheme == .dark, seed: settings.seed)
        let children = Array(node.children.prefix(visibleCount).enumerated())
        return VStack(spacing: 0) {
            if node.children.isEmpty {
                Text("Nessun contenuto")
                    .font(.m3BodyMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            ForEach(children, id: \.element.id) { i, child in
                NodeRow(
                    node: child,
                    fraction: child.fraction(of: node.size),
                    color: colorizer.swatch(for: child, topIndex: i),
                    units: settings.units,
                    showThumbnail: source == .photos && child.kind == .asset
                ) {
                    open(index: i, rect: nil)
                }
                .contextMenu { rowMenu(child, index: i) }
                if i < children.count - 1 {
                    Divider().overlay(m3.outlineVariant).padding(.leading, 64)
                }
            }
            if node.children.count > visibleCount {
                Button {
                    visibleCount += 200
                } label: {
                    Text("Mostra altri \(Fmt.count(min(200, node.children.count - visibleCount)))")
                        .font(.m3LabelLarge)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private func rowMenu(_ child: StorageNode, index: Int) -> some View {
        if child.isContainer {
            Button { open(index: index, rect: nil) } label: { Label("Apri", systemImage: "arrow.down.right.and.arrow.up.left") }
        } else {
            Button { selection = LeafSelection(node: child, location: location(of: validPath)) } label: { Label("Dettagli", systemImage: "info.circle") }
        }
        if case .folder = source {
            Button(role: .destructive) { askDelete([child]) } label: { Label("Elimina", systemImage: "trash") }
        } else if !child.isContainer {
            Button(role: .destructive) { Task { await model.delete([child], from: source) } } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    private var typesPanel: some View {
        let node = current
        let stats = cache.extensions(node)
        let colorizer = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: settings.seed)
        return VStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 12) {
                    CategorySwatch(color: colorizer.leaf(category: s.category, ext: s.ext, topIndex: 0, depth: 1, id: "").base, icon: s.category.icon)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.label)
                                .font(.m3TitleSmall)
                                .foregroundStyle(m3.onSurface)
                            Text(s.description)
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(model.bytes(s.size))
                                .font(.m3LabelLarge)
                                .foregroundStyle(m3.onSurface)
                        }
                        HStack {
                            Text(Fmt.plural(s.count, "file", "file"))
                            Spacer()
                            Text(Fmt.percent(node.size > 0 ? Double(s.size) / Double(node.size) : 0))
                        }
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        PercentBar(fraction: node.size > 0 ? Double(s.size) / Double(node.size) : 0, color: colorizer.leaf(category: s.category, ext: s.ext, topIndex: 0, depth: 1, id: "").base)
                    }
                }
                .padding(.vertical, 10)
                if i < stats.count - 1 {
                    Divider().overlay(m3.outlineVariant).padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var largestPanel: some View {
        let node = current
        let items = cache.largest(node)
        let colorizer = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: settings.seed)
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, ref in
                NodeRow(
                    node: ref.node,
                    fraction: ref.node.fraction(of: node.size),
                    color: colorizer.swatch(for: ref.node, topIndex: 0),
                    units: settings.units,
                    showThumbnail: source == .photos,
                    subtitleOverride: ref.location.isEmpty ? nil : ref.location,
                    rank: i + 1
                ) {
                    selection = LeafSelection(node: ref.node, location: location(of: validPath + Array(ref.path.dropLast())))
                }
                .contextMenu {
                    Button(role: .destructive) {
                        if case .folder = source { askDelete([ref.node]) } else { Task { await model.delete([ref.node], from: source) } }
                    } label: { Label("Elimina", systemImage: "trash") }
                }
                if i < items.count - 1 {
                    Divider().overlay(m3.outlineVariant).padding(.leading, 64)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Route.duplicates(source)) {
                Image(systemName: "square.on.square")
            }
            .accessibilityLabel("Possibili doppioni")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Colori", selection: settingBinding(\.colorMode)) {
                    ForEach(TreemapColorMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Livelli nella mappa", selection: settingBinding(\.depth)) {
                    ForEach(1...4, id: \.self) { Text(Fmt.plural($0, "livello", "livelli")).tag($0) }
                }
                Toggle("Etichette", isOn: settingBinding(\.labels))
                Toggle("Effetto cuscino 3D", isOn: settingBinding(\.cushion))
                if source == .photos {
                    Toggle("Miniature delle foto", isOn: settingBinding(\.thumbnails))
                }
                Divider()
                Button {
                    model.rescan(source)
                } label: {
                    Label("Analizza di nuovo", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    private func settingBinding<V>(_ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0 })
    }

    // MARK: - Navigation

    private func location(of path: [Int]) -> String {
        ([root.name] + root.trail(path).map(\.name)).joined(separator: " › ")
    }

    /// Tap on a block or a row: zoom into containers, open leaves.
    private func open(index: Int, rect: CGRect?) {
        let node = current
        guard node.children.indices.contains(index) else { return }
        let child = node.children[index]
        guard child.isContainer else {
            selection = LeafSelection(node: child, location: location(of: validPath))
            return
        }
        let r = rect ?? childRect(in: node, index: index)
        let w = max(1, mapSize.width), h = max(1, mapSize.height)
        let start = ZoomTransform(sx: max(0.01, r.width / w), sy: max(0.01, r.height / h), tx: r.minX, ty: r.minY)
        animateZoom(from: start, opacity: 0.35) { path = validPath + [index] }
    }

    /// Back to the level `level` of the breadcrumb (0 = root), zooming out.
    private func goUp(to level: Int) {
        let p = validPath
        guard level < p.count else { return }
        let target = Array(p.prefix(level))
        let childIndex = p[level]
        guard let parent = root.node(at: target) else { return }
        let r = childRect(in: parent, index: childIndex)
        let w = max(1, mapSize.width), h = max(1, mapSize.height)
        let sx = w / max(1, r.width), sy = h / max(1, r.height)
        let start = ZoomTransform(sx: sx, sy: sy, tx: -r.minX * sx, ty: -r.minY * sy)
        animateZoom(from: start, opacity: 0.5) { path = target }
    }

    private func animateZoom(from start: ZoomTransform, opacity: Double, change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            change()
            zoom = start
            mapOpacity = opacity
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(response: 0.48, dampingFraction: 0.9)) {
                zoom = .identity
                mapOpacity = 1
            }
        }
    }

    /// Rect of a depth-1 block of `parent` in the current map size.
    private func childRect(in parent: StorageNode, index: Int) -> CGRect {
        let w = max(1, mapSize.width), h = max(1, mapSize.height)
        let rects = Treemap.squarify(parent.children.map { Double($0.size) }, in: TMRect(x: 0, y: 0, w: w, h: h))
        guard rects.indices.contains(index), rects[index].area > 0 else {
            return CGRect(x: w / 2 - 10, y: h / 2 - 10, width: 20, height: 20)
        }
        let r = rects[index]
        return CGRect(x: r.x, y: r.y, width: r.w, height: r.h)
    }

    // MARK: - Delete

    private func askDelete(_ nodes: [StorageNode]) {
        pendingDelete = nodes
        showDeleteConfirm = true
    }

    private var deleteTitle: String {
        guard let first = pendingDelete.first else { return "" }
        let bytes = model.bytes(pendingDelete.reduce(0) { $0 + $1.size })
        if pendingDelete.count == 1 {
            return first.isContainer ? "Eliminare la cartella “\(first.name)” (\(bytes)) e tutto il suo contenuto?" : "Eliminare “\(first.name)” (\(bytes))?"
        }
        return "Eliminare \(pendingDelete.count) elementi (\(bytes))?"
    }
}

/// One row of the content / biggest lists.
struct NodeRow: View {
    @Environment(\.m3) private var m3
    let node: StorageNode
    let fraction: Double
    let color: Color
    let units: ByteUnits
    var showThumbnail = false
    var subtitleOverride: String?
    var rank: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(node.name)
                            .font(.m3TitleSmall)
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(Fmt.bytes(node.size, units: units))
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurface)
                            .monospacedDigit()
                    }
                    HStack {
                        Text(subtitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(Fmt.percent(fraction))
                            .monospacedDigit()
                    }
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    PercentBar(fraction: fraction, color: color, height: 5)
                }
                if node.isContainer {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var leading: some View {
        if showThumbnail && node.kind == .asset {
            AssetThumbnail(id: node.id, pixels: 120)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) { rankBadge }
        } else {
            CategorySwatch(color: color, icon: node.isContainer ? "folder.fill" : node.category.icon, size: 44)
                .overlay(alignment: .topLeading) { rankBadge }
        }
    }

    @ViewBuilder
    private var rankBadge: some View {
        if let rank {
            Text("\(rank)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(m3.onPrimary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(m3.primary, in: Capsule())
                .offset(x: -4, y: -4)
        }
    }

    private var subtitle: String {
        if let subtitleOverride { return subtitleOverride }
        if node.isContainer {
            if let detail = node.detail { return detail }
            var s = Fmt.plural(node.fileCount, "elemento", "elementi")
            if let d = node.modified { s += " · " + Fmt.date(d) }
            return s
        }
        var parts: [String] = []
        if let detail = node.detail { parts.append(detail) } else { parts.append(FileCategory.describe(ext: node.ext, category: node.category)) }
        if let d = node.modified { parts.append(Fmt.date(d)) }
        return parts.joined(separator: " · ")
    }
}
