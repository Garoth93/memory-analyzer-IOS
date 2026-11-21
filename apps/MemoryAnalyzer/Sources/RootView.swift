import SwiftUI
import StorageCore

/// Navigation targets shared by the tabs.
enum Route: Hashable {
    case explorer(ExplorerSource)
    case duplicates(ExplorerSource)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Panoramica", systemImage: "internaldrive.fill", value: AppTab.overview) {
                NavigationStack { OverviewView().withRoutes() }
            }
            Tab("Foto", systemImage: "photo.stack.fill", value: AppTab.photos) {
                NavigationStack { PhotosView().withRoutes() }
            }
            Tab("Cartelle", systemImage: "folder.fill", value: AppTab.folders) {
                FoldersView()
            }
            Tab("Impostazioni", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .alert("Attenzione", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
    }
}

extension View {
    /// Destinations reachable from any tab.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .explorer(let source): SourceExplorer(source: source)
            case .duplicates(let source): DuplicatesView(source: source)
            }
        }
    }
}

/// Explorer for a source, or a placeholder when its scan is gone.
struct SourceExplorer: View {
    @Environment(AppModel.self) private var model
    let source: ExplorerSource

    var body: some View {
        if let root = model.root(for: source) {
            ExplorerView(source: source, root: root) {
                if case .folder(let id) = source, let scan = model.folderScans[id] {
                    ScanProgressCard(
                        title: "Analisi in corso…",
                        detail: "\(Fmt.count(scan.progress.done)) file · \(model.bytes(scan.progress.bytes))",
                        fraction: nil
                    ) { model.cancelFolderScan(id) }
                }
            }
        } else {
            EmptyStateView(icon: "questionmark.folder.fill", title: "Analisi non disponibile", message: "Questa analisi è stata rimossa.")
        }
    }
}
