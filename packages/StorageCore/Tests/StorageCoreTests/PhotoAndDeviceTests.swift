import XCTest
@testable import StorageCore

final class PhotoAndDeviceTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ y: Int, _ m: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = 15; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: c)!
    }

    private func items() -> [PhotoItem] {
        [
            PhotoItem(id: "v1", filename: "IMG_0001.MOV", kind: .video, date: date(2024, 3), size: 900, pixelWidth: 1920, pixelHeight: 1080, duration: 65),
            PhotoItem(id: "p1", filename: "IMG_0002.HEIC", kind: .photo, date: date(2024, 3), size: 100, pixelWidth: 4032, pixelHeight: 3024, isFavorite: true),
            PhotoItem(id: "s1", filename: "IMG_0003.PNG", kind: .screenshot, date: date(2024, 7), size: 50),
            PhotoItem(id: "l1", filename: "IMG_0004.HEIC", kind: .livePhoto, date: date(2023, 1), size: 300, isHidden: true),
            PhotoItem(id: "x1", filename: "", kind: .photo, date: nil, size: 10)
        ]
    }

    func testDateGrouping() {
        let tree = PhotoTreeBuilder.build(items(), grouping: .date, timeZone: utc)
        XCTAssertEqual(tree.size, 1360)
        XCTAssertEqual(tree.fileCount, 5)
        XCTAssertEqual(tree.children.map(\.name), ["2024", "2023", "Senza data"])
        let y2024 = tree.children[0]
        XCTAssertEqual(y2024.children.map(\.name), ["Marzo 2024", "Luglio 2024"])
        XCTAssertEqual(y2024.children[0].children.map(\.id), ["v1", "p1"])
        let video = y2024.children[0].children[0]
        XCTAssertEqual(video.kind, .asset)
        XCTAssertEqual(video.category, .video)
        XCTAssertEqual(video.ext, "mov")
        XCTAssertEqual(video.detail, "1920×1080 · 1:05")
        XCTAssertEqual(video.ref, "v1")
        // Undated assets are not split by month; unnamed ones get the kind label.
        XCTAssertEqual(tree.children[2].children.first?.name, "Foto")
        XCTAssertEqual(y2024.category, .video)
    }

    func testKindGrouping() {
        let tree = PhotoTreeBuilder.build(items(), grouping: .kind, timeZone: utc)
        XCTAssertEqual(tree.children.first?.name, "Video")
        XCTAssertEqual(Set(tree.children.map(\.name)), ["Video", "Live Photo", "Foto", "Screenshot"])
        let photos = tree.children.first { $0.name == "Foto" }!
        XCTAssertEqual(photos.children.map(\.name), ["2024", "Senza data"])
        XCTAssertEqual(photos.children[0].children.first?.kind, .asset)
    }

    func testSummary() {
        let s = PhotoSummary(items())
        XCTAssertEqual(s.totalCount, 5)
        XCTAssertEqual(s.totalSize, 1360)
        XCTAssertEqual(s.videoCount, 1)
        XCTAssertEqual(s.photoCount, 4)
        XCTAssertEqual(s.favoriteCount, 1)
        XCTAssertEqual(s.hiddenCount, 1)
        XCTAssertEqual(s.rows.first?.kind, .video)
        XCTAssertEqual(s.oldest, date(2023, 1))
        XCTAssertEqual(s.newest, date(2024, 7))
        XCTAssertEqual(PhotoSummary([]).totalCount, 0)
    }

    func testDiskUsage() {
        let d = DiskUsage(total: 476, available: 137)
        XCTAssertEqual(d.used, 339)
        XCTAssertEqual(d.usedFraction, 339.0 / 476.0, accuracy: 1e-9)
        XCTAssertEqual(DiskUsage(total: 10, available: 50).available, 10)
        XCTAssertEqual(DiskUsage(total: 0, available: 0).usedFraction, 0)
    }

    func testDeviceMapClampsToUsedSpace() {
        let disk = DiskUsage(total: 1000, available: 400)
        let map = DeviceMap.build(.init(disk: disk, photos: 250, folders: [(id: "f1", name: "Download", bytes: 100)], app: 20))
        XCTAssertEqual(map.size, 1000)
        XCTAssertEqual(map.children.map(\.id), [DeviceMap.freeID, DeviceMap.photosID, DeviceMap.systemID, DeviceMap.foldersID, DeviceMap.appID])
        XCTAssertEqual(map.children.first { $0.id == DeviceMap.systemID }?.size, 230)
        let folders = map.children.first { $0.id == DeviceMap.foldersID }!
        XCTAssertEqual(folders.children.first?.ref, "f1")
        XCTAssertEqual(folders.category, .document)

        // Photo originals in iCloud can exceed the used space: clamp.
        let big = DeviceMap.build(.init(disk: disk, photos: 5000, app: 20))
        XCTAssertEqual(big.size, 1000)
        XCTAssertEqual(big.children.first { $0.id == DeviceMap.photosID }?.size, 600)
        XCTAssertNil(big.children.first { $0.id == DeviceMap.appID })
        XCTAssertNil(big.children.first { $0.id == DeviceMap.systemID })

        let none = DeviceMap.build(.init(disk: disk))
        XCTAssertEqual(none.children.map(\.id), [DeviceMap.systemID, DeviceMap.freeID])
    }
}
