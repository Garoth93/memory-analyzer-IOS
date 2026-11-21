import SwiftUI
import StorageCore

// Material 3 theme generated from the seed color.

extension Color {
    init(rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// Accent / container / on-container colors of one role.
struct Tones: Sendable {
    let accent: Color
    let onAccent: Color
    let container: Color
    let onContainer: Color

    /// Material 3 tones generated from any hex color.
    init(hex: String, dark: Bool) {
        let p = TonalPalette(hex: hex)
        accent = Color(rgb: p.tone(dark ? 80 : 40))
        onAccent = Color(rgb: p.tone(dark ? 20 : 100))
        container = Color(rgb: p.tone(dark ? 30 : 90))
        onContainer = Color(rgb: p.tone(dark ? 90 : 10))
    }

    init(accent: Color, onAccent: Color, container: Color, onContainer: Color) {
        self.accent = accent
        self.onAccent = onAccent
        self.container = container
        self.onContainer = onContainer
    }
}

/// Material 3 color roles generated from the seed color.
struct M3Theme: Sendable {
    let dark: Bool
    let primary: Color
    let onPrimary: Color
    let primaryContainer: Color
    let onPrimaryContainer: Color
    let secondaryContainer: Color
    let onSecondaryContainer: Color
    let tertiary: Color
    let tertiaryContainer: Color
    let onTertiaryContainer: Color
    let surface: Color
    let surfaceContainerLowest: Color
    let surfaceContainerLow: Color
    let surfaceContainer: Color
    let surfaceContainerHigh: Color
    let surfaceContainerHighest: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let outline: Color
    let outlineVariant: Color
    let error: Color
    let onError: Color
    let errorContainer: Color
    let onErrorContainer: Color
    let success: Color
    let successContainer: Color
    let onSuccessContainer: Color
    let warning: Color
    let warningContainer: Color
    let onWarningContainer: Color

    init(seed: String, dark: Bool) {
        let s = MaterialScheme(seed: seed, dark: dark)
        self.dark = dark
        primary = Color(rgb: s.primary)
        onPrimary = Color(rgb: s.onPrimary)
        primaryContainer = Color(rgb: s.primaryContainer)
        onPrimaryContainer = Color(rgb: s.onPrimaryContainer)
        secondaryContainer = Color(rgb: s.secondaryContainer)
        onSecondaryContainer = Color(rgb: s.onSecondaryContainer)
        tertiary = Color(rgb: s.tertiary)
        tertiaryContainer = Color(rgb: s.tertiaryContainer)
        onTertiaryContainer = Color(rgb: s.onTertiaryContainer)
        surface = Color(rgb: s.surface)
        surfaceContainerLowest = Color(rgb: s.surfaceContainerLowest)
        surfaceContainerLow = Color(rgb: s.surfaceContainerLow)
        surfaceContainer = Color(rgb: s.surfaceContainer)
        surfaceContainerHigh = Color(rgb: s.surfaceContainerHigh)
        surfaceContainerHighest = Color(rgb: s.surfaceContainerHighest)
        onSurface = Color(rgb: s.onSurface)
        onSurfaceVariant = Color(rgb: s.onSurfaceVariant)
        outline = Color(rgb: s.outline)
        outlineVariant = Color(rgb: s.outlineVariant)
        error = Color(rgb: s.error)
        onError = Color(rgb: dark ? TonalPalette(hue: 32, chroma: 80).tone(20) : RGBColor(red: 1, green: 1, blue: 1))
        errorContainer = Color(rgb: s.errorContainer)
        onErrorContainer = Color(rgb: s.onErrorContainer)
        success = Color(rgb: s.success)
        successContainer = Color(rgb: s.successContainer)
        onSuccessContainer = Color(rgb: s.onSuccessContainer)
        warning = Color(rgb: s.warning)
        warningContainer = Color(rgb: s.warningContainer)
        onWarningContainer = Color(rgb: s.onWarningContainer)
    }

    static let fallback = M3Theme(seed: Palette.defaultAccent, dark: false)

    func tones(_ hex: String) -> Tones { Tones(hex: hex, dark: dark) }

    /// Positive state.
    var positive: Tones { Tones(accent: success, onAccent: dark ? onSuccessContainer : .white, container: successContainer, onContainer: onSuccessContainer) }
    /// Destructive actions.
    var danger: Tones { Tones(accent: error, onAccent: onError, container: errorContainer, onContainer: onErrorContainer) }
    var neutral: Tones { Tones(accent: onSurfaceVariant, onAccent: surface, container: surfaceContainerHighest, onContainer: onSurface) }
    var primaryTones: Tones { Tones(accent: primary, onAccent: onPrimary, container: primaryContainer, onContainer: onPrimaryContainer) }
    var tertiaryTones: Tones { Tones(accent: tertiary, onAccent: surface, container: tertiaryContainer, onContainer: onTertiaryContainer) }
}

extension EnvironmentValues {
    @Entry var m3: M3Theme = .fallback
}

/// Material 3 type scale, with the rounded system face for an expressive look.
extension Font {
    static let m3DisplaySmall = Font.system(size: 36, weight: .bold, design: .rounded)
    static let m3HeadlineLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let m3HeadlineMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let m3HeadlineSmall = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let m3TitleLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let m3TitleMedium = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let m3TitleSmall = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let m3BodyLarge = Font.system(size: 17, weight: .regular)
    static let m3BodyMedium = Font.system(size: 15, weight: .regular)
    static let m3BodySmall = Font.system(size: 13, weight: .regular)
    static let m3LabelLarge = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let m3LabelMedium = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let m3LabelSmall = Font.system(size: 11, weight: .medium, design: .rounded)
}

/// Scalloped "cookie" shape from the Material 3 Expressive shape set.
struct CookieShape: Shape {
    var lobes: Int = 9
    var depth: CGFloat = 0.06

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        let r0 = base * (1 - depth)
        var p = Path()
        let steps = 240
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi - .pi / 2
            let r = r0 + base * depth * cos(Double(lobes) * a)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Icon on a tonal rounded square (or cookie).
struct IconBadge: View {
    let icon: String
    let tones: Tones
    var size: CGFloat = 44
    var cookie = false
    var filled = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(width: size, height: size)
            .background {
                if cookie {
                    CookieShape().fill(filled ? tones.accent : tones.container)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous).fill(filled ? tones.accent : tones.container)
                }
            }
    }
}

// MARK: - Map colors

/// Colors of one block: cushion gradient (light → dark) and label color.
struct TileColors {
    let light: Color
    let base: Color
    let dark: Color
    let text: Color
    let secondaryText: Color
}

/// Computes (and caches) the colors of the map blocks.
/// Reference type so the Canvas closure can memoize without state changes.
final class TileColorizer {
    let mode: TreemapColorMode
    let dark: Bool
    let seedHue: Double
    private var cache: [String: TileColors] = [:]

    init(mode: TreemapColorMode, dark: Bool, seed: String) {
        self.mode = mode
        self.dark = dark
        self.seedHue = TonalPalette(hex: seed).hue
    }

    /// Stable small hash (FNV-1a) used to vary the tone of sibling blocks.
    static func hash(_ s: String) -> Int {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 {
            h ^= UInt32(b)
            h = h &* 16_777_619
        }
        return Int(h % 1000)
    }

    /// Frame color of an expanded container (its children are drawn inside).
    func container(depth: Int) -> TileColors {
        let key = "c\(depth)"
        if let c = cache[key] { return c }
        let p = TonalPalette(hue: seedHue, chroma: 6)
        let tone = dark ? 14.0 + Double(depth) * 5 : 90.0 - Double(depth) * 5
        let colors = TileColors(
            light: Color(rgb: p.tone(tone + 3)),
            base: Color(rgb: p.tone(tone)),
            dark: Color(rgb: p.tone(tone - 3)),
            text: Color(rgb: p.tone(dark ? 92 : 12)),
            secondaryText: Color(rgb: p.tone(dark ? 75 : 35))
        )
        cache[key] = colors
        return colors
    }

    /// Fill of a block drawn as a leaf of the map (file, asset or collapsed folder).
    func leaf(category: FileCategory, ext: String, topIndex: Int, depth: Int, id: String) -> TileColors {
        let palette: TonalPalette
        var tone: Double
        let key: String
        switch mode {
        case .type:
            let variant = ext.isEmpty ? 0 : (Self.hash(ext) % 3) - 1
            key = "t\(category.rawValue)\(variant)"
            palette = category.palette
            tone = (dark ? 52 : 62) + Double(variant) * 6
            if category == .free { tone = dark ? 30 : 88 }
            if category == .system || category == .other || category == .folder { tone = dark ? 40 : 70 }
        case .folder:
            let variant = depth <= 1 ? 0 : (Self.hash(id) % 3) - 1
            key = "f\(topIndex % 24)|\(variant)|\(category == .free)"
            palette = TonalPalette(hue: Palette.folderHue(index: topIndex, seedHue: seedHue), chroma: category == .free ? 20 : 55)
            tone = (dark ? 50 : 62) + Double(variant) * 7
            if category == .free { tone = dark ? 30 : 88 }
        }
        if let c = cache[key] { return c }
        let lightText = tone < 58
        let colors = TileColors(
            light: Color(rgb: palette.tone(min(98, tone + 12))),
            base: Color(rgb: palette.tone(tone)),
            dark: Color(rgb: palette.tone(max(5, tone - 14))),
            text: Color(rgb: palette.tone(lightText ? 99 : 10)),
            secondaryText: Color(rgb: palette.tone(lightText ? 92 : 25))
        )
        cache[key] = colors
        return colors
    }

    /// Swatch color for lists and legends.
    func swatch(for node: StorageNode, topIndex: Int) -> Color {
        leaf(category: node.category, ext: node.ext, topIndex: topIndex, depth: 1, id: node.id).base
    }

    func swatch(category: FileCategory) -> Color {
        TileColorizer(mode: .type, dark: dark, seed: "#4f5bd5")
            .leaf(category: category, ext: "", topIndex: 0, depth: 1, id: "").base
    }
}
