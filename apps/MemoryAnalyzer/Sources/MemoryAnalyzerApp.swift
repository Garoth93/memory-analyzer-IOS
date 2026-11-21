import SwiftUI
import StorageCore

@main
struct MemoryAnalyzerApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .task { await model.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.loaded { Task { await model.refreshDevice() } }
        }
    }
}

/// Builds the Material palette for the current light/dark appearance.
private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch model.settings.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let theme = M3Theme(seed: model.settings.seed, dark: scheme == .dark)
        RootView()
            .environment(\.m3, theme)
            .tint(theme.primary)
            .preferredColorScheme(model.settings.appearance == .system ? nil : scheme)
    }
}
