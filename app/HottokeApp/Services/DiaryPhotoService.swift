import Photos
import UIKit

/// 「写真リンク」: その日撮った写真を検索し、サムネイルを表示するための読み取り専用アクセス。
/// 写真ファイル自体はアプリ内にコピー・保存しない。表示のたびにPhotosフレームワークからその場で
/// 取得するだけで、外部への送信も一切行わない。
enum DiaryPhotoService {
    /// 1枚の写真（サムネイル表示・拡大表示に必要な最小限の情報）。
    struct Item: Identifiable, Equatable {
        let id: String // PHAsset.localIdentifier
        let asset: PHAsset

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    /// 読み取り権限がすでにあるか（`.limited`＝一部の写真のみ許可、も利用可能として扱う）。
    static func isAuthorized() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// 必要なら許可ダイアログを出す。すでに拒否済みなら、ダイアログは出さずfalseを返す
    /// （端末の設定アプリから変更してもらう必要がある）。
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }
        guard status == .notDetermined else { return false }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return newStatus == .authorized || newStatus == .limited
    }

    /// 指定の日に撮影された写真（新しい順、最大`limit`枚）。権限がなければ空配列。
    static func photos(on day: Date, calendar: Calendar = .current, limit: Int = 3) -> [Item] {
        guard isAuthorized() else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var items: [Item] = []
        result.enumerateObjects { asset, _, _ in
            items.append(Item(id: asset.localIdentifier, asset: asset))
        }
        return items
    }

    /// 小さいサムネイル画像を取得する（PHImageManagerのキャッシュに任せる。ファイルには保存しない）。
    static func requestThumbnail(for asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        PHImageManager.default().requestImage(
            for: asset, targetSize: size, contentMode: .aspectFill, options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// タップして拡大表示するための、画面に収まる大きさの画像を取得する。
    static func requestDisplayImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: UIScreen.main.bounds.width * scale, height: UIScreen.main.bounds.height * scale)
        PHImageManager.default().requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
        ) { image, _ in
            completion(image)
        }
    }
}
