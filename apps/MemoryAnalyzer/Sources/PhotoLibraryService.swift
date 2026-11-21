import Foundation
import Photos
import UIKit
import AVKit
import StorageCore

/// Thread-safe cancel flag shared with the background scans.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Reads the photo library with PhotoKit (sizes, kinds, thumbnails, deletion).
enum PhotoLibraryService {
    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Measures every asset. Runs synchronously: call it from a background task.
    static func scan(includeHidden: Bool, flag: CancelFlag, progress: @escaping @Sendable (Int, Int) -> Void) -> [PhotoItem]? {
        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHidden
        options.includeAllBurstAssets = true
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        let total = result.count
        var items: [PhotoItem] = []
        items.reserveCapacity(total)
        progress(0, total)
        for index in 0..<total {
            if index % 150 == 0 {
                if flag.isCancelled { return nil }
                progress(index, total)
            }
            autoreleasepool {
                let asset = result.object(at: index)
                items.append(item(for: asset))
            }
        }
        progress(total, total)
        return items
    }

    static func item(for asset: PHAsset) -> PhotoItem {
        let resources = PHAssetResource.assetResources(for: asset)
        var size: Int64 = 0
        for r in resources {
            // `fileSize` is not public API but is the size iOS reports for the resource.
            if let n = r.value(forKey: "fileSize") as? NSNumber { size += n.int64Value }
        }
        let main = resources.first { [.photo, .video, .fullSizePhoto, .fullSizeVideo].contains($0.type) } ?? resources.first
        return PhotoItem(
            id: asset.localIdentifier,
            filename: main?.originalFilename ?? "",
            kind: kind(of: asset),
            date: asset.creationDate ?? asset.modificationDate,
            size: size,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden
        )
    }

    static func kind(of asset: PHAsset) -> PhotoMediaKind {
        let s = asset.mediaSubtypes
        if asset.mediaType == .video {
            if s.contains(.videoHighFrameRate) { return .slowMotion }
            if s.contains(.videoTimelapse) { return .timelapse }
            return .video
        }
        if s.contains(.photoScreenshot) { return .screenshot }
        if s.contains(.photoLive) { return .livePhoto }
        if s.contains(.photoPanorama) { return .panorama }
        return .photo
    }

    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Deletes the assets; iOS asks the user to confirm. Returns false if cancelled.
    static func delete(ids: [String]) async throws -> Bool {
        guard !ids.isEmpty else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch let error as NSError where error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.userCancelled.rawValue {
            return false
        }
    }

    static func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = asset(id) else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { cont in
            let once = OnceFlag()
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                if once.claim() { cont.resume(returning: item) }
            }
        }
    }
}

/// Guards continuations against handlers called more than once.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Thumbnails of photo assets, cached in memory.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 600
    }

    func image(for id: String, pixels: CGFloat) async -> UIImage? {
        let bucket = max(64, min(1200, (pixels / 64).rounded(.up) * 64))
        let key = "\(id)|\(Int(bucket))" as NSString
        if let img = cache.object(forKey: key) { return img }
        guard let asset = PhotoLibraryService.asset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: bucket, height: bucket)
        let image: UIImage? = await withCheckedContinuation { cont in
            let once = OnceFlag()
            manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { img, _ in
                if once.claim() { cont.resume(returning: img) }
            }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
