import SwiftUI
import StorageCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Aspetto")
                M3Card {
                    VStack(alignment: .leading, spacing: 16) {
                        M3Segmented(options: Appearance.allCases.map { (value: $0, title: $0.label, icon: icon(for: $0)) }, selection: binding(\.appearance))
                        Text("Colore principale")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                        HStack(spacing: 10) {
                            ForEach(Palette.seeds, id: \.self) { hex in
                                let selected = model.settings.seed == hex
                                Button {
                                    withAnimation(.spring(response: 0.3)) { model.settings.seed = hex }
                                } label: {
                                    Circle()
                                        .fill(Color(rgb: RGBColor(hex: hex) ?? RGBColor(red: 0.5, green: 0.5, blue: 0.5)))
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            if selected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .heavy))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(selected ? m3.onSurface : .clear, lineWidth: 2))
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel("Colore \(hex)")
                            }
                        }
                    }
                }

                SectionTitle("Mappa a blocchi")
                M3Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Colori dei blocchi")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                        M3Segmented(options: [
                            (value: TreemapColorMode.type, title: "Per tipo", icon: "doc.on.doc"),
                            (value: TreemapColorMode.folder, title: "Per cartella", icon: "folder")
                        ], selection: binding(\.colorMode))
                        Stepper(value: binding(\.depth), in: 1...4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Livelli visibili: \(model.settings.depth)")
                                    .font(.m3BodyLarge)
                                    .foregroundStyle(m3.onSurface)
                                Text("Quante sottocartelle disegnare dentro ogni blocco")
                                    .font(.m3BodySmall)
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        toggle("Effetto cuscino 3D", "Sfumature come in WizTree", binding(\.cushion))
                        toggle("Etichette", "Nome e dimensione sui blocchi grandi", binding(\.labels))
                        toggle("Miniature delle foto", "Mostra le foto dentro i blocchi", binding(\.thumbnails))
                        toggle("Vibrazione", "Feedback quando entri in un blocco", binding(\.haptics))
                        Text("Unità di misura")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                        M3Segmented(options: [
                            (value: ByteUnits.decimal, title: "1 GB = 1000 MB", icon: "iphone"),
                            (value: ByteUnits.binary, title: "1 GB = 1024 MB", icon: "pc")
                        ], selection: binding(\.units))
                    }
                }

                SectionTitle("Foto e video")
                M3Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Raggruppa per")
                            .font(.m3LabelLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                        M3Segmented(options: [
                            (value: PhotoGrouping.date, title: "Anno e mese", icon: "calendar"),
                            (value: PhotoGrouping.kind, title: "Tipo e anno", icon: "square.stack")
                        ], selection: binding(\.photoGrouping))
                        toggle("Includi foto nascoste", "Vale dalla prossima analisi", binding(\.includeHidden))
                    }
                }

                SectionTitle("Dati")
                M3Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Spazio usato da questa app")
                                .font(.m3BodyMedium)
                                .foregroundStyle(m3.onSurface)
                            Spacer()
                            Text(model.bytes(model.appSize))
                                .font(.m3LabelLarge)
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        PillButton(title: "Cancella analisi salvate", icon: "trash", tones: m3.danger, filled: false, height: 46) {
                            confirmClear = true
                        }
                        Text("Cancella solo i risultati delle analisi: foto e file restano dove sono.")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }

                SectionTitle("Informazioni")
                M3Card(color: m3.surfaceContainer) {
                    VStack(alignment: .leading, spacing: 10) {
                        infoRow("Cosa posso analizzare", "Foto e video della libreria e qualsiasi cartella dell'app File (Sul mio iPhone, iCloud Drive, USB, rete).")
                        infoRow("Cosa no", "Le altre app e i loro dati: iOS li protegge. Il totale è in Impostazioni › Generali › Spazio iPhone e qui appare come “Sistema, app e altri dati”.")
                        infoRow("Privacy", "Tutto resta sul telefono: nessun dato viene inviato.")
                        HStack {
                            Text("Versione")
                            Spacer()
                            Text(DeviceInfo.appVersion)
                        }
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(m3.surface)
        .navigationTitle("Impostazioni")
        .confirmationDialog("Cancellare tutte le analisi salvate?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Cancella", role: .destructive) { model.clearAllScans() }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func binding<V>(_ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0 })
    }

    private func icon(for a: Appearance) -> String {
        switch a {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private func toggle(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.m3BodyLarge)
                    .foregroundStyle(m3.onSurface)
                Text(subtitle)
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .tint(m3.primary)
    }

    private func infoRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.m3TitleSmall)
                .foregroundStyle(m3.onSurface)
            Text(text)
                .font(.m3BodySmall)
                .foregroundStyle(m3.onSurfaceVariant)
        }
    }
}
