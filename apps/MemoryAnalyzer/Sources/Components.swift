import SwiftUI
import StorageCore

// MARK: - Surfaces

/// Material 3 card: tonal surface, large continuous corners.
struct M3Card<Content: View>: View {
    @Environment(\.m3) private var m3
    var color: Color?
    var padding: CGFloat
    var corner: CGFloat
    let content: Content

    init(color: Color? = nil, padding: CGFloat = 16, corner: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.color = color
        self.padding = padding
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct SectionTitle: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Buttons

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Material 3 filled / tonal pill button.
struct PillButton: View {
    let title: String
    let icon: String
    let tones: Tones
    var filled = true
    var height: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.m3LabelLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(filled ? tones.accent : tones.container, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Round tonal icon button (Material "filled tonal icon button").
struct TonalIconButton: View {
    @Environment(\.m3) private var m3
    let icon: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(m3.onSecondaryContainer)
                .frame(width: size, height: size)
                .background(m3.secondaryContainer, in: Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Small Material "assist chip" with an icon.
struct InfoChip: View {
    @Environment(\.m3) private var m3
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.m3LabelMedium)
                .lineLimit(1)
        }
        .foregroundStyle(m3.onSurfaceVariant)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(m3.surfaceContainerHigh, in: Capsule())
    }
}

/// Material 3 segmented button.
struct M3Segmented<Value: Hashable>: View {
    @Environment(\.m3) private var m3
    let options: [(value: Value, title: String, icon: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selected ? "checkmark" : option.icon)
                            .font(.system(size: 13, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(option.title)
                            .font(.m3LabelLarge)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurface)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? m3.secondaryContainer : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(m3.outline).frame(width: 1)
                }
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(m3.outline, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Data bits

/// Thin rounded bar showing a share (0…1).
struct PercentBar: View {
    @Environment(\.m3) private var m3
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(m3.surfaceContainerHighest)
                Capsule()
                    .fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// Rounded color square with the category icon.
struct CategorySwatch: View {
    let color: Color
    let icon: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.opacity(0.85), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
    }
}

/// Big number + unit headline ("354,3" "GB").
struct SizeHeadline: View {
    @Environment(\.m3) private var m3
    let bytes: Int64
    let units: ByteUnits
    var font: Font = .m3DisplaySmall

    var body: some View {
        let parts = Fmt.bytesParts(bytes, units: units)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.number)
                .font(font)
                .foregroundStyle(m3.onSurface)
                .contentTransition(.numericText())
            Text(parts.unit)
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurfaceVariant)
        }
    }
}

// MARK: - Toast

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    let icon: String
    let style: Style
}

struct ToastView: View {
    @Environment(\.m3) private var m3
    let toast: Toast

    var body: some View {
        let tones: Tones = {
            switch toast.style {
            case .success: return m3.positive
            case .info: return Tones(accent: m3.primary, onAccent: m3.onPrimary, container: m3.surfaceContainerHighest, onContainer: m3.onSurface)
            case .error: return m3.danger
            }
        }()
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .bold))
            Text(toast.message)
                .font(.m3LabelLarge)
                .lineLimit(2)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(tones.container, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - Empty state

struct EmptyStateView<Actions: View>: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let message: String
    let actions: Actions

    init(icon: String, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(icon: icon, tones: m3.primaryTones, size: 96, cookie: true)
                .padding(.bottom, 4)
            Text(title)
                .font(.m3TitleLarge)
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
            actions
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

/// Progress card shown while a scan runs.
struct ScanProgressCard: View {
    @Environment(\.m3) private var m3
    let title: String
    let detail: String
    /// nil = indeterminate.
    let fraction: Double?
    let onCancel: () -> Void

    var body: some View {
        M3Card(color: m3.primaryContainer) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(m3.onPrimaryContainer)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.m3TitleSmall)
                        Text(detail)
                            .font(.m3BodySmall)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Button("Annulla", action: onCancel)
                        .font(.m3LabelLarge)
                }
                .foregroundStyle(m3.onPrimaryContainer)
                if let fraction {
                    ProgressView(value: min(1, max(0, fraction)))
                        .tint(m3.primary)
                }
            }
        }
    }
}
