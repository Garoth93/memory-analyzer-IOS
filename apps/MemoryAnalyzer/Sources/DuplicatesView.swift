import SwiftUI
import StorageCore

/// Probable duplicates: same size and name (files) or same size and
/// resolution (photos). Keeps the oldest copy, deletes the others.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let source: ExplorerSource

    @State private var groups: [DuplicateGroup]?
    @State private var pending: DuplicateGroup?
    @State private var limit = 40

    private var root: StorageNode? { model.root(for: source) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let groups {
                    if groups.isEmpty {
                        EmptyStateView(icon: "checkmark.seal.fill", title: "Nessun doppione", message: "Non ho trovato elementi con stessa dimensione e stesso nome o risoluzione.")
                    } else {
                        header(groups)
                        ForEach(groups.prefix(limit)) { group in
                            groupCard(group)
                        }
                        if groups.count > limit {
                            Button("Mostra altri gruppi") { limit += 40 }
                                .font(.m3LabelLarge)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                } else {
                    ProgressView("Cerco i doppioni…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(m3.surface)
        .navigationTitle("Possibili doppioni")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(root?.size ?? 0)|\(root?.fileCount ?? 0)") {
            guard let root else { groups = []; return }
            let result = await Task.detached(priority: .userInitiated) { Analysis.duplicates(root) }.value
            withAnimation { groups = result }
        }
        .confirmationDialog(
            pending.map { "Eliminare \($0.items.count - 1) copie (\(model.bytes($0.reclaimable)))?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Elimina copie", role: .destructive) {
                if let g = pending { Task { await model.delete(g.items.dropFirst().map(\.node), from: source) } }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Resta la copia più vecchia.")
        }
    }

    private func header(_ groups: [DuplicateGroup]) -> some View {
        let total = groups.reduce(Int64(0)) { $0 + $1.reclaimable }
        return M3Card(color: m3.tertiaryContainer, padding: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Puoi recuperare")
                    .font(.m3TitleSmall)
                SizeHeadline(bytes: total, units: model.settings.units)
                Text("\(Fmt.plural(groups.count, "gruppo", "gruppi")) di elementi uguali")
                    .font(.m3BodyMedium)
            }
            .foregroundStyle(m3.onTertiaryContainer)
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        M3Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(group.items.count) copie · \(model.bytes(group.size)) l'una")
                        .font(.m3TitleSmall)
                        .foregroundStyle(m3.onSurface)
                    Spacer()
                    Text("−\(model.bytes(group.reclaimable))")
                        .font(.m3LabelLarge)
                        .foregroundStyle(m3.error)
                }
                ForEach(Array(group.items.enumerated()), id: \.element.id) { i, ref in
                    HStack(spacing: 10) {
                        if source == .photos {
                            AssetThumbnail(id: ref.node.id, pixels: 120)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            CategorySwatch(color: m3.secondaryContainer, icon: ref.node.category.icon, size: 44)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.node.name)
                                .font(.m3BodyMedium)
                                .foregroundStyle(m3.onSurface)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text([ref.location, ref.node.modified.map { Fmt.date($0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if i == 0 {
                            Text("Tieni")
                                .font(.m3LabelSmall)
                                .foregroundStyle(m3.onSuccessContainer)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(m3.successContainer, in: Capsule())
                        }
                    }
                }
                PillButton(title: "Elimina \(group.items.count - 1) copie", icon: "trash", tones: m3.danger, filled: false, height: 44) {
                    if source == .photos {
                        Task { await model.delete(group.items.dropFirst().map(\.node), from: source) }
                    } else {
                        pending = group
                    }
                }
            }
        }
    }
}
