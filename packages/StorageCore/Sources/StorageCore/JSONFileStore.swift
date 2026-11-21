import Foundation

/// Minimal JSON persistence for any `Codable` value.
/// Used by the app to save its state in Application Support; used by
/// tests with a temporary directory. Works on Linux.
public struct JSONFileStore<Value: Codable> {
    public let url: URL
    /// Compact output for big files (scan trees); pretty-printed otherwise.
    public let compact: Bool

    public init(url: URL, compact: Bool = false) {
        self.url = url
        self.compact = compact
    }

    /// Returns `nil` when the file does not exist yet.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(Value.self, from: data)
    }

    /// Writes atomically, creating the parent directory if needed.
    public func save(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = Self.encoder
        if compact { encoder.outputFormatting = [] }
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// Removes the file if present.
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
