import XCTest
@testable import StorageCore

final class FormatTests: XCTestCase {
    func testBytesDecimal() {
        XCTAssertEqual(Fmt.bytes(0), "0 byte")
        XCTAssertEqual(Fmt.bytes(999), "999 byte")
        XCTAssertEqual(Fmt.bytes(1000), "1,0 KB")
        XCTAssertEqual(Fmt.bytes(1_500), "1,5 KB")
        XCTAssertEqual(Fmt.bytes(732_300_000), "732,3 MB")
        XCTAssertEqual(Fmt.bytes(354_300_000_000), "354,3 GB")
        XCTAssertEqual(Fmt.bytes(999_960_000), "1,0 GB")
        XCTAssertEqual(Fmt.bytes(2_000_000_000_000), "2,0 TB")
        XCTAssertEqual(Fmt.bytes(-5), "0 byte")
    }

    func testBytesBinary() {
        XCTAssertEqual(Fmt.bytes(1023, units: .binary), "1023 byte")
        XCTAssertEqual(Fmt.bytes(1024, units: .binary), "1,0 KB")
        XCTAssertEqual(Fmt.bytes(476 * 1_073_741_824, units: .binary), "476,0 GB")
        XCTAssertEqual(Fmt.bytes(Int64(72.0 * 1_073_741_824), units: .binary), "72,0 GB")
        let parts = Fmt.bytesParts(Int64(338.9 * 1_073_741_824), units: .binary)
        XCTAssertEqual(parts.number, "338,9")
        XCTAssertEqual(parts.unit, "GB")
    }

    func testNumbers() {
        XCTAssertEqual(Fmt.count(1_933_024), "1.933.024")
        XCTAssertEqual(Fmt.count(371), "371")
        XCTAssertEqual(Fmt.count(-1200), "-1.200")
        XCTAssertEqual(Fmt.percent(0.712), "71,2 %")
        XCTAssertEqual(Fmt.percent(1), "100,0 %")
        XCTAssertEqual(Fmt.percent(0.0049, digits: 0), "0 %")
        XCTAssertEqual(Fmt.decimal(1234.56, digits: 2), "1.234,56")
        XCTAssertEqual(Fmt.decimal(.nan, digits: 1), "0")
        XCTAssertEqual(Fmt.plural(1, "file", "file"), "1 file")
        XCTAssertEqual(Fmt.plural(3, "cartella", "cartelle"), "3 cartelle")
    }

    func testDates() {
        let utc = TimeZone(identifier: "UTC")!
        // 2026-11-21 23:57 UTC
        let d = Date(timeIntervalSince1970: 1_795_305_420)
        XCTAssertEqual(Fmt.dateTime(d, timeZone: utc), "21/11/2026 23:57")
        XCTAssertEqual(Fmt.date(d, timeZone: utc), "21/11/2026")
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-30), now: now), "adesso")
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-600), now: now), "10 min fa")
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-3_700), now: now), "1 ora fa")
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-90_000), now: now), "ieri")
        XCTAssertEqual(Fmt.relative(now.addingTimeInterval(-5 * 86_400), now: now), "5 giorni fa")
        XCTAssertEqual(Fmt.duration(65), "1:05")
        XCTAssertEqual(Fmt.duration(3723), "1:02:03")
    }

    func testCategories() {
        XCTAssertEqual(FileCategory.classify(ext: "MOV"), .video)
        XCTAssertEqual(FileCategory.classify(ext: ".heic"), .image)
        XCTAssertEqual(FileCategory.classify(ext: "dll"), .app)
        XCTAssertEqual(FileCategory.classify(ext: "wad"), .archive)
        XCTAssertEqual(FileCategory.classify(ext: "xyz"), .other)
        XCTAssertEqual(FileCategory.ext(of: "IMG_0001.HEIC"), "heic")
        XCTAssertEqual(FileCategory.ext(of: ".gitignore"), "")
        XCTAssertEqual(FileCategory.ext(of: "README"), "")
        XCTAssertEqual(FileCategory.ext(of: "archive.tar.gz"), "gz")
        XCTAssertEqual(FileCategory.ext(of: "strange.name with space"), "")
        XCTAssertEqual(FileCategory.describe(ext: "mov", category: .video), "Video MOV")
        XCTAssertEqual(FileCategory.describe(ext: "", category: .other), "File senza estensione")
        for c in FileCategory.allCases {
            XCTAssertFalse(c.label.isEmpty)
            XCTAssertFalse(c.icon.isEmpty)
        }
    }

    func testPalette() {
        let p = TonalPalette(hex: Palette.defaultAccent)
        XCTAssertGreaterThan(p.chroma, 30)
        let light = MaterialScheme(seed: Palette.defaultAccent, dark: false)
        let dark = MaterialScheme(seed: Palette.defaultAccent, dark: true)
        XCTAssertNotEqual(light.surface, dark.surface)
        XCTAssertEqual(RGBColor(hex: "#4f5bd5")?.hex, "#4f5bd5")
        XCTAssertEqual(Palette.folderHue(index: 0, seedHue: 10), 10)
        XCTAssertEqual(Palette.folderHue(index: 3, seedHue: 300), (300 + 3 * 137.508).truncatingRemainder(dividingBy: 360), accuracy: 1e-9)
        for s in Palette.seeds { XCTAssertNotNil(RGBColor(hex: s)) }
    }
}
