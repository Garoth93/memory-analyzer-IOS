import SwiftUI
import UniformTypeIdentifiers
import StorageCore

/// Folders chosen in Files: list, add, rescan, remove.
struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var importing = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(newScans) { scan in
                        ScanProgressCard(
                            title: "Analizzo “\(scan.name)”…",
                            detail: "\(Fmt.count(scan.progress.done)) file · \(model.bytes(scan.progress.bytes)) · \(scan.progress.current)",
                            fraction: nil
                        ) { model.cancelFolderScan(scan.id) }
                    }
                    if model.folders.isEmpty && newScans.isEmpty {
                        EmptyStateView(
                            icon: "folder.badge.plus",
                            title: "Nessuna cartella",
                            message: "Scegli una cartella dall'app File: “Sul mio iPhone”, iCloud Drive, una chiavetta USB o un disco di rete. La analizzo tutta, sottocartelle comprese."
                        ) {
                            PillButton(title: "Scegli cartella", icon: "folder.badge.plus", tones: m3.primaryTones) { importing = true }
                        }
                    } else {
                        if !model.folders.isEmpty {
                            totalHeader
                        }
                        ForEach(model.folders) { record in
                            NavigationLink(value: Route.explorer(.folder(record.id))) {
                                FolderCard(record: record, scanning: model.folderScans[record.id] != nil)
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button { model.rescanFolder(record.id) } label: { Label("Analizza di nuovo", systemImage: "arrow.clockwise") }
                                Button(role: .destructive) { model.removeFolder(record.id) } label: { Label("Rimuovi dall'elenco", systemImage: "minus.circle") }
                            }
                        }
                    }
                    tipCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(m3.surface)
            .navigationTitle("Cartelle")
            .withRoutes()
            .overlay(alignment: .bottomTrailing) {
                if !model.folders.isEmpty || !newScans.isEmpty {
                    Button { importing = true } label: {
                        Label("Aggiungi", systemImage: "plus")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onPrimaryContainer)
                            .padding(.horizontal, 20)
                            .frame(height: 56)
                            .background(m3.primaryContainer, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(20)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { model.addFolder(url) }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Scans of folders that are not in the list yet.
    private var newScans: [PendingScan] {
        model.folderScans
            .filter { entry in !model.folders.contains { $0.id == entry.key } }
            .map { PendingScan(id: $0.key, name: $0.value.name, progress: $0.value.progress) }
            .sorted { $0.name < $1.name }
    }

    private var totalHeader: some View {
        let total = model.folders.reduce(Int64(0)) { $0 + $1.root.size }
        let files = model.folders.reduce(0) { $0 + $1.root.fileCount }
        return VStack(alignment: .leading, spacing: 2) {
            SizeHeadline(bytes: total, units: model.settings.units, font: .m3HeadlineLarge)
            Text("\(Fmt.plural(model.folders.count, "cartella", "cartelle")) · \(Fmt.plural(files, "file", "file"))")
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var tipCard: some View {
        M3Card(color: m3.surfaceContainer) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggerimento")
                        .font(.m3TitleSmall)
                        .foregroundStyle(m3.onSurface)
                    Text("Per vedere tutto ciò che hai salvato sul telefono scegli la cartella principale “Sul mio iPhone”. Le cartelle iCloud non scaricate occupano 0 byte sul telefono: lo vedi in “Allocati”.")
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(m3.tertiary)
            }
        }
        .padding(.top, 8)
    }
}

struct PendingScan: Identifiable {
    let id: UUID
    let name: String
    let progress: RunningScan
}

struct FolderCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.colorScheme) private var colorScheme
    let record: FolderScanRecord
    let scanning: Bool

    var body: some View {
        let colorizer = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: model.settings.seed)
        // Cheap category mix from the top-level blocks (dominant category of each).
        let cats = Dictionary(grouping: record.root.children, by: \.category)
            .map { CategoryStat(category: $0.key, size: $0.value.reduce(0) { $0 + $1.size }, count: $0.value.count) }
            .sorted { $0.size > $1.size }
            .prefix(6)
        M3Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(icon: record.isLocal ? "iphone" : "icloud.fill", tones: m3.primaryTones, size: 46, cookie: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name)
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                        Text("\(Fmt.plural(record.root.fileCount, "file", "file")) · \(Fmt.plural(record.root.folderCount, "cartella", "cartelle"))")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                        if let n = record.unreadable, n > 0 {
                            Label(Fmt.plural(n, "non leggibile", "non leggibili"), systemImage: "exclamationmark.triangle.fill")
                                .font(.m3LabelSmall)
                                .foregroundStyle(m3.warning)
                        }
                    }
                    Spacer()
                    if scanning {
                        ProgressView()
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.bytes(record.root.size))
                                .font(.m3TitleMedium)
                                .foregroundStyle(m3.onSurface)
                            Text(Fmt.relative(record.date))
                                .font(.m3LabelSmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                    }
                }
                // Category mix as a stacked bar.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(cats)) { c in
                            let w = geo.size.width * (record.root.size > 0 ? Double(c.size) / Double(record.root.size) : 0)
                            if w >= 1 {
                                Rectangle()
                                    .fill(colorizer.leaf(category: c.category, ext: "", topIndex: 0, depth: 1, id: "").base)
                                    .frame(width: max(2, w - 2))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10)
                .background(m3.surfaceContainerHighest)
                .clipShape(Capsule())
            }
        }
    }
}
