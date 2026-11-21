import SwiftUI
import Photos
import StorageCore

/// Photo library: scan, summary per kind and the block map.
struct PhotosView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        Group {
            if let tree = model.photoTree {
                ExplorerView(source: .photos, root: tree) {
                    VStack(spacing: 12) {
                        if let scan = model.photoScan { progressCard(scan) }
                        if let summary = model.photoSummary { PhotoSummaryCard(summary: summary) }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let scan = model.photoScan {
                            progressCard(scan)
                                .padding(.top, 24)
                        } else if !model.loaded {
                            ProgressView().padding(.top, 80)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .background(m3.surface)
                .navigationTitle("Foto e video")
            }
        }
    }

    private func progressCard(_ scan: RunningScan) -> some View {
        ScanProgressCard(
            title: "Misuro foto e video…",
            detail: scan.total.map { "\(Fmt.count(scan.done)) di \(Fmt.count($0))" } ?? "Preparazione…",
            fraction: scan.fraction
        ) { model.cancelPhotoScan() }
    }

    @ViewBuilder
    private var emptyState: some View {
        let denied = model.photoStatus == .denied || model.photoStatus == .restricted
        EmptyStateView(
            icon: denied ? "lock.fill" : "photo.stack.fill",
            title: denied ? "Accesso alle foto negato" : "Analizza la libreria",
            message: denied
                ? "Consenti l'accesso a “Tutte le foto” in Impostazioni per misurare foto e video."
                : "Misuro ogni foto e video (originali, modifiche e Live Photo) e li disegno a blocchi: i più grandi saltano subito all'occhio."
        ) {
            if denied {
                PillButton(title: "Apri Impostazioni", icon: "gear", tones: m3.primaryTones) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else {
                PillButton(title: "Analizza foto e video", icon: "sparkle.magnifyingglass", tones: m3.primaryTones) {
                    Task { await model.scanPhotos() }
                }
            }
        }
        M3Card(color: m3.surfaceContainer) {
            Label {
                Text("Con “Ottimizza spazio iPhone” attivo, la dimensione indicata è quella degli originali su iCloud: sul telefono possono occupare meno.")
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
            } icon: {
                Image(systemName: "icloud")
                    .foregroundStyle(m3.primary)
            }
        }
    }
}

/// Totals per media kind, with mini bars.
struct PhotoSummaryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.colorScheme) private var colorScheme
    let summary: PhotoSummary

    var body: some View {
        let colorizer = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: model.settings.seed)
        M3Card(color: m3.surfaceContainerLow) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    InfoChip(icon: "photo.fill", text: Fmt.plural(summary.photoCount, "foto", "foto"))
                    InfoChip(icon: "video.fill", text: Fmt.plural(summary.videoCount, "video", "video"))
                    if summary.favoriteCount > 0 {
                        InfoChip(icon: "heart.fill", text: Fmt.count(summary.favoriteCount))
                    }
                }
                ForEach(summary.rows) { row in
                    let color = colorizer.leaf(category: row.kind.category, ext: "", topIndex: 0, depth: 1, id: "").base
                    HStack(spacing: 10) {
                        Image(systemName: row.kind.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 20)
                        Text(row.kind.label)
                            .font(.m3BodyMedium)
                            .foregroundStyle(m3.onSurface)
                            .frame(width: 92, alignment: .leading)
                        PercentBar(fraction: summary.totalSize > 0 ? Double(row.size) / Double(summary.totalSize) : 0, color: color, height: 8)
                        Text(model.bytes(row.size))
                            .font(.m3LabelMedium)
                            .foregroundStyle(m3.onSurfaceVariant)
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                if let r = model.photoRecord {
                    Text("Analizzate \(Fmt.relative(r.date)) in \(Fmt.decimal(r.elapsed, digits: 1)) s")
                        .font(.m3LabelSmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            }
        }
    }
}
