import SwiftUI
import AVKit
import QuickLook
import StorageCore

/// Details of a single file or photo, with preview, share and delete.
struct ItemDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let source: ExplorerSource
    let node: StorageNode
    let location: String
    let rootSize: Int64

    @State private var previewURL: URL?
    @State private var fileURL: URL?
    @State private var player: AVPlayer?
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text(node.name)
                            .font(.m3HeadlineSmall)
                            .foregroundStyle(m3.onSurface)
                            .textSelection(.enabled)
                        Text(location)
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                            .lineLimit(2)
                    }
                    infoCard
                    actions
                }
                .padding(16)
            }
            .background(m3.surface)
            .navigationTitle(FileCategory.describe(ext: node.ext, category: node.category))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .quickLookPreview($previewURL)
        .task { resolveFileURL() }
        .onDisappear { player?.pause() }
        .confirmationDialog("Eliminare “\(node.name)” (\(model.bytes(node.size)))?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { performDelete() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il file verrà rimosso definitivamente dalla cartella.")
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        let colors = TileColorizer(mode: .type, dark: colorScheme == .dark, seed: model.settings.seed)
            .leaf(category: node.category, ext: node.ext, topIndex: 0, depth: 1, id: node.id)
        if source == .photos {
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    AssetThumbnail(id: node.id, pixels: 1000)
                    if node.category == .video {
                        Button {
                            Task { await loadVideo() }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 68, height: 68)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            ZStack {
                LinearGradient(colors: [colors.light, colors.base, colors.dark], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 10) {
                    Image(systemName: node.category.icon)
                        .font(.system(size: 54, weight: .semibold))
                    Text(node.ext.isEmpty ? "FILE" : node.ext.uppercased())
                        .font(.m3TitleMedium)
                }
                .foregroundStyle(colors.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private var infoCard: some View {
        M3Card {
            VStack(spacing: 12) {
                row("Dimensione", model.bytes(node.size), icon: "internaldrive.fill")
                if source != .photos {
                    row("Allocati su disco", node.allocated == 0 ? "0 byte (solo su iCloud?)" : model.bytes(node.allocated), icon: "square.stack.3d.down.right.fill")
                }
                row("Byte", Fmt.count(Int(node.size)), icon: "number")
                row("Quota del totale", Fmt.percent(node.fraction(of: rootSize), digits: 2), icon: "chart.pie.fill")
                row("Tipo", node.category.label, icon: node.category.icon)
                if let detail = node.detail {
                    row(node.category == .video ? "Risoluzione · durata" : "Risoluzione", detail, icon: "aspectratio.fill")
                }
                if let d = node.modified {
                    row(source == .photos ? "Scattata il" : "Modificato il", Fmt.dateTime(d), icon: "calendar")
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(m3.primary)
                .frame(width: 22)
            Text(title)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
            Spacer()
            Text(value)
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if source == .photos {
                PillButton(title: "Apri l'app Foto", icon: "photo.on.rectangle.angled", tones: m3.primaryTones, filled: false) {
                    if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
                }
                PillButton(title: deleting ? "Eliminazione…" : "Elimina dalla libreria", icon: "trash.fill", tones: m3.danger) {
                    performDelete()
                }
                Text("iOS chiede conferma; l'elemento finisce in “Eliminati di recente” per 30 giorni: svuotalo per liberare davvero lo spazio.")
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
            } else {
                HStack(spacing: 10) {
                    PillButton(title: "Anteprima", icon: "eye.fill", tones: m3.primaryTones) {
                        previewURL = fileURL
                    }
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Condividi")
                                    .font(.m3LabelLarge)
                            }
                            .foregroundStyle(m3.onSecondaryContainer)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(m3.secondaryContainer, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                PillButton(title: "Elimina file", icon: "trash.fill", tones: m3.danger) {
                    confirmDelete = true
                }
            }
        }
    }

    // MARK: - Actions

    private func resolveFileURL() {
        guard case .folder(let id) = source, let record = model.folders.first(where: { $0.id == id }) else { return }
        fileURL = try? FolderAccess.url(of: node, in: record)
    }

    private func loadVideo() async {
        guard let item = await PhotoLibraryService.playerItem(for: node.id) else { return }
        let p = AVPlayer(playerItem: item)
        player = p
        p.play()
    }

    private func performDelete() {
        guard !deleting else { return }
        deleting = true
        Task {
            let removed = await model.delete([node], from: source)
            deleting = false
            if removed > 0 { dismiss() }
        }
    }
}
