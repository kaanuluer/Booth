import AVFoundation
import Foundation
import UIKit

enum MediaMetadata {
    static func write(
        to url: URL,
        title: String,
        artwork: UIImage?,
        chapters: [Marker]
    ) async {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent("meta-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: dest)

        let fileType: AVFileType
        switch url.pathExtension.lowercased() {
        case "m4a", "aac": fileType = .m4a
        case "wav": fileType = .wav
        default: fileType = .aiff
        }

        var items: [AVMetadataItem] = []
        items.append(item(key: AVMetadataKey.commonKeyTitle, value: title))
        items.append(item(key: AVMetadataKey.commonKeyArtist, value: "Booth"))
        if let artwork, let data = artwork.jpegData(compressionQuality: 0.86) {
            items.append(artworkItem(data))
        }
        for chapter in chapters.sorted(by: { $0.time < $1.time }) where chapter.isChapter {
            let meta = AVMutableMetadataItem()
            meta.identifier = .quickTimeUserDataComment
            meta.value = "\(TimeCode.format(chapter.time)) \(chapter.label)" as NSString
            items.append(meta)
        }
        session.metadata = items
        do {
            try await session.export(to: dest, as: fileType)
            guard FileManager.default.fileExists(atPath: dest.path) else { return }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: dest, to: url)
        } catch {
            try? FileManager.default.removeItem(at: dest)
        }
    }

    private static func item(key: AVMetadataKey, value: String) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = key as NSString
        item.value = value as NSString
        return item
    }

    private static func artworkItem(_ data: Data) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeyArtwork as NSString
        item.value = data as NSData
        item.dataType = kCMMetadataBaseDataType_JPEG as String
        return item
    }
}
