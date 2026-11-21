import Foundation

/// How bytes are converted into KB / MB / GB.
public enum ByteUnits: String, Codable, CaseIterable, Sendable {
    /// 1 GB = 1000³ byte, like iOS Settings.
    case decimal
    /// 1 GB = 1024³ byte, like Windows and WizTree.
    case binary

    public var base: Double { self == .decimal ? 1000 : 1024 }

    public var label: String {
        switch self {
        case .decimal: return "Decimali (come iOS)"
        case .binary: return "Binarie (come Windows)"
        }
    }
}

/// Italian number formatting, independent from the device locale so the
/// tests on Linux give the same strings as the app.
public enum Fmt {
    private static let units = ["KB", "MB", "GB", "TB", "PB"]

    /// "354,3 GB", "732,3 MB", "512 byte".
    public static func bytes(_ value: Int64, units: ByteUnits = .decimal) -> String {
        let base = units.base
        let v = Double(max(0, value))
        if v < base { return "\(Int(v)) byte" }
        var scaled = v / base
        var index = 0
        while index < Self.units.count - 1 {
            // Rounded to one decimal it must stay below `base`.
            if (scaled * 10).rounded() / 10 < base { break }
            scaled /= base
            index += 1
        }
        return "\(decimal(scaled, digits: 1)) \(Self.units[index])"
    }

    /// Size split into number and unit for big headlines ("354,3", "GB").
    public static func bytesParts(_ value: Int64, units: ByteUnits = .decimal) -> (number: String, unit: String) {
        let s = bytes(value, units: units)
        guard let space = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<space]), String(s[s.index(after: space)...]))
    }

    /// "71,2 %" (fraction 0…1).
    public static func percent(_ fraction: Double, digits: Int = 1) -> String {
        "\(decimal(fraction * 100, digits: digits)) %"
    }

    /// "1.933.024".
    public static func count(_ value: Int) -> String {
        let s = String(abs(value))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }

    /// Fixed decimals with a comma ("12,5").
    public static func decimal(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "0" }
        let factor = pow(10.0, Double(digits))
        let rounded = (abs(value) * factor).rounded()
        let intPart = Int64(rounded / factor)
        let fracPart = Int64(rounded) - intPart * Int64(factor)
        var s = count(Int(intPart))
        if digits > 0 {
            var frac = String(fracPart)
            while frac.count < digits { frac = "0" + frac }
            s += "," + frac
        }
        return value < 0 && rounded > 0 ? "-" + s : s
    }

    /// "1 elemento" / "12 elementi" style plurals.
    public static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(count(n)) \(n == 1 ? one : many)"
    }

    public static let monthNames = [
        "Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno",
        "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"
    ]

    /// "21/11/2026 23:57" in the given time zone.
    public static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        func two(_ v: Int?) -> String { let n = v ?? 0; return n < 10 ? "0\(n)" : "\(n)" }
        return "\(two(c.day))/\(two(c.month))/\(c.year ?? 0) \(two(c.hour)):\(two(c.minute))"
    }

    /// "21/11/2026".
    public static func date(_ date: Date, timeZone: TimeZone = .current) -> String {
        String(dateTime(date, timeZone: timeZone).prefix(10))
    }

    /// "3 min fa", "ieri", "5 giorni fa".
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "adesso"
        case ..<3600: return "\(Int(s / 60)) min fa"
        case ..<86_400: return Int(s / 3600) == 1 ? "1 ora fa" : "\(Int(s / 3600)) ore fa"
        case ..<172_800: return "ieri"
        default: return "\(Int(s / 86_400)) giorni fa"
        }
    }

    /// "1:05" / "1:02:03" for video durations.
    public static func duration(_ seconds: Double) -> String {
        let t = Int(max(0, seconds).rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 {
            let mm = m < 10 ? "0\(m)" : "\(m)"
            return "\(h):\(mm):\(ss)"
        }
        return "\(m):\(ss)"
    }
}
