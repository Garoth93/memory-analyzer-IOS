import SwiftUI
import StorageCore

/// Home: device capacity, map of the iPhone and shortcuts to the analyses.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.colorScheme) private var colorScheme
    @State private var info: InfoTopic?

    enum InfoTopic: String, Identifiable {
        case system, free, app
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let disk = model.disk {
                    capacityCard(disk)
                }
                if let tree = model.deviceTree {
                    SectionTitle("Mappa dell'iPhone", trailing: "tocca un blocco")
                    M3Card(color: m3.surfaceContainerHigh, padding: 6) {
                        TreemapView(
                            node: tree,
                            depth: 2,
                            colorMode: .type,
                            cushion: model.settings.cushion,
                            labels: true,
                            units: model.settings.units,
                            corner: 22
                        ) { tile in
                            handleTap(tile)
                        }
                        .frame(height: 300)
                    }
                }
                SectionTitle("Analisi")
                photosCard
                foldersCard
                otherAppsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(m3.surface)
        .navigationTitle("Memoria")
        .refreshable { await model.refreshDevice() }
        .sheet(item: $info) { topic in
            InfoSheet(topic: topic)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Capacity

    private func capacityCard(_ disk: DiskUsage) -> some View {
        M3Card(color: m3.primaryContainer, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iPhone")
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                        let used = Fmt.bytesParts(disk.used, units: model.settings.units)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(used.number)
                                .font(.m3DisplaySmall)
                                .contentTransition(.numericText())
                            Text("\(used.unit) usati")
                                .font(.m3TitleMedium)
                        }
                        .foregroundStyle(m3.onPrimaryContainer)
                        Text("su \(model.bytes(disk.total)) · \(model.bytes(disk.available)) liberi")
                            .font(.m3BodyMedium)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.85))
                    }
                    Spacer()
                    UsageRing(fraction: disk.usedFraction, color: m3.primary, track: m3.onPrimaryContainer.opacity(0.15))
                        .frame(width: 76, height: 76)
                }
                if let tree = model.deviceTree {
                    CapacityBar(tree: tree, dark: colorScheme == .dark, seed: model.settings.seed)
                        .frame(height: 14)
                    legend(tree)
                }
            }
        }
    }

    private func legend(_ tree: StorageNode) -> some View {
        let colorizer = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: model.settings.seed)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(tree.children) { child in
                HStack(spacing: 8) {
                    Circle()
                        .fill(colorizer.swatch(for: child, topIndex: 0))
                        .frame(width: 10, height: 10)
                    Text(child.name)
                        .font(.m3BodyMedium)
                    Spacer()
                    Text(model.bytes(child.size))
                        .font(.m3LabelLarge)
                        .monospacedDigit()
                }
                .foregroundStyle(m3.onPrimaryContainer)
            }
        }
    }

    // MARK: - Cards

    private var photosCard: some View {
        Button {
            if model.photoTree != nil {
                model.tab = .photos
            } else {
                model.tab = .photos
                Task { await model.scanPhotos() }
            }
        } label: {
            M3Card {
                HStack(spacing: 14) {
                    IconBadge(icon: "photo.stack.fill", tones: m3.tones("#d4a72c"), size: 52, cookie: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Foto e video")
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onSurface)
                        if let scan = model.photoScan {
                            Text(scan.total.map { "Analisi \(Fmt.count(scan.done)) di \(Fmt.count($0))…" } ?? "Analisi in corso…")
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                        } else if let s = model.photoSummary, let r = model.photoRecord {
                            Text("\(Fmt.plural(s.photoCount, "foto", "foto")) · \(Fmt.plural(s.videoCount, "video", "video"))")
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                            Text("Analizzate \(Fmt.relative(r.date))")
                                .font(.m3LabelSmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                        } else {
                            Text("Scopri quali foto e video occupano più spazio")
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                    }
                    Spacer()
                    if let s = model.photoSummary, model.photoScan == nil {
                        Text(model.bytes(s.totalSize))
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onSurface)
                    } else if model.photoScan != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(m3.primary)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var foldersCard: some View {
        Button {
            model.tab = .folders
        } label: {
            M3Card {
                HStack(spacing: 14) {
                    IconBadge(icon: "folder.fill", tones: m3.tones("#0969da"), size: 52, cookie: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cartelle di File")
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onSurface)
                        Text(model.folders.isEmpty
                             ? "Analizza “Sul mio iPhone”, iCloud Drive o qualsiasi cartella"
                             : Fmt.plural(model.folders.count, "cartella analizzata", "cartelle analizzate"))
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                    if !model.folders.isEmpty {
                        Text(model.bytes(model.folders.reduce(0) { $0 + $1.root.size }))
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onSurface)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(m3.primary)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var otherAppsCard: some View {
        Button { info = .system } label: {
            M3Card(color: m3.surfaceContainer) {
                HStack(spacing: 14) {
                    IconBadge(icon: "square.grid.3x3.fill", tones: m3.neutral, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("E le altre app?")
                            .font(.m3TitleSmall)
                            .foregroundStyle(m3.onSurface)
                        Text("iOS non permette di misurare le altre app: scopri dove vederle.")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func handleTap(_ tile: TreemapTile) {
        switch tile.id {
        case DeviceMap.photosID: model.tab = .photos
        case DeviceMap.foldersID: model.tab = .folders
        case DeviceMap.freeID: info = .free
        case DeviceMap.appID: info = .app
        default: info = .system
        }
    }
}

/// Explanations for the blocks that cannot be explored.
private struct InfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let topic: OverviewView.InfoTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IconBadge(icon: icon, tones: m3.primaryTones, size: 56, cookie: true)
            Text(title)
                .font(.m3HeadlineSmall)
                .foregroundStyle(m3.onSurface)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m3.surfaceContainerLow)
    }

    private var icon: String {
        switch topic {
        case .system: return "gearshape.2.fill"
        case .free: return "circle.dashed"
        case .app: return "app.badge.fill"
        }
    }

    private var title: String {
        switch topic {
        case .system: return "Sistema, app e altri dati"
        case .free: return "Spazio libero"
        case .app: return "Questa app"
        }
    }

    private var message: String {
        switch topic {
        case .system:
            return "È lo spazio usato da iOS, dalle app installate e dai loro dati (chat, cache, download, giochi). Per sicurezza iOS non permette a nessuna app di leggere i dati delle altre: il dettaglio per app lo trovi in Impostazioni › Generali › Spazio iPhone. Le foto e le cartelle che analizzi qui vengono tolte da questo blocco."
        case .free:
            return "Spazio disponibile per nuovi dati, come lo calcola iOS (include lo spazio che il sistema può liberare da solo, per esempio le cache)."
        case .app:
            return "Spazio occupato da questa app: il programma e le analisi salvate (\(model.bytes(model.appSize))). Puoi cancellare le analisi da Impostazioni."
        }
    }
}

/// Stacked bar of the device map's top-level blocks.
struct CapacityBar: View {
    let tree: StorageNode
    let dark: Bool
    let seed: String

    var body: some View {
        let colorizer = TileColorizer(mode: .type, dark: dark, seed: seed)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(tree.children) { child in
                    let w = geo.size.width * child.fraction(of: tree.size)
                    if w >= 1 {
                        Rectangle()
                            .fill(colorizer.swatch(for: child, topIndex: 0))
                            .frame(width: max(2, w - 2))
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

/// Circular gauge with the used percentage.
struct UsageRing: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(Fmt.percent(fraction, digits: 0))
                .font(.m3LabelLarge)
                .foregroundStyle(color)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fraction)
    }
}
