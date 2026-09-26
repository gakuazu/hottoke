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

    /// 現在の読み取り権限の状態。
    static func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 読み取り権限がすでにあるか（`.limited`＝一部の写真のみ許可、も利用可能として扱う）。
    static func isAuthorized() -> Bool {
        let status = authorizationStatus()
        return status == .authorized || status == .limited
    }

    /// `DiaryPhotoStrip`が画面に何を出すかの状態（権限の状態・その日の写真の有無から決まる、
    /// Photosフレームワークの実際のデータを使わない純粋な判定）。
    /// オーナー実機フィードバック対応: 以前は権限待ち・拒否・0枚のいずれも「エリアを完全に隠す」
    /// 扱いだったため、状態が画面から分からなくなっていた。この関数で状態を明確に分ける。
    enum AccessPresentation: Equatable {
        /// 許可済みで、その日の写真がある（サムネイルを並べる）。
        case thumbnails
        /// 許可済みだが、その日の写真が0枚。
        case noPhotosThisDay
        /// まだ許可を聞いていない（その場でもう一度ダイアログを出す導線を出せる）。
        case needsPermission
        /// 明確に拒否されている（設定アプリへ誘導する）。
        case denied
        /// 制限されている（スクリーンタイム等。設定アプリでは変更できないことが多い）。
        case restricted
    }

    static func presentation(for status: PHAuthorizationStatus, hasPhotosThisDay: Bool) -> AccessPresentation {
        switch status {
        case .authorized, .limited:
            return hasPhotosThisDay ? .thumbnails : .noPhotosThisDay
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .needsPermission
        @unknown default:
            return .needsPermission
        }
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
