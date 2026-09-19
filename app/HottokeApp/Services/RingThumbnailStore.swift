import UIKit

/// アーカイブのサムネイル（文字なしの小さな点描リング）を、ディスクにキャッシュする。
/// キャッシュは Caches/ring-thumbs に「テーマ-日付-内容の署名」のファイル名で置く。
/// 内容（記録）が変わったときだけ作り直す（今日は更新のたびに署名が変わるので、作り直される）。
final class RingThumbnailStore {
    static let shared = RingThumbnailStore()
    static let thumbnailSize: CGFloat = 240

    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ring-thumbs", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func fileName(styleKey: String, slices: DailyRingSlices) -> String {
        "\(styleKey)-\(slices.dateKey)-\(slices.signature).png"
    }

    /// キャッシュがあれば返し、なければ描いて保存して返す。同じ日・テーマの古いキャッシュは消す。
    /// 描画に時間がかかるので、バックグラウンドで呼ぶこと。
    func thumbnail(styleKey: String, slices: DailyRingSlices, style: RingArtStyle = .flowerCorona) -> UIImage {
        let name = fileName(styleKey: styleKey, slices: slices)
        let url = directory.appendingPathComponent(name)
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        let image = DailyRingRenderer.renderThumbnail(slices: slices, size: Self.thumbnailSize, style: style)
        removeOldCaches(styleKey: styleKey, dateKey: slices.dateKey)
        if let data = image.pngData() {
            try? data.write(to: url, options: .atomic)
        }
        return image
    }

    private func removeOldCaches(styleKey: String, dateKey: String) {
        let prefix = "\(styleKey)-\(dateKey)-"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}

/// カレンダーに表示するサムネイルを、バックグラウンドで用意して公開する。
@MainActor
final class ArchiveThumbnailProvider: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    private var signatures: [String: String] = [:]

    /// 指定の記録のサムネイルを用意する（すでに同じ内容のものがあれば何もしない）。
    func load(records: [DailyRingSlices], style: RingArtStyle) async {
        let todo = records.filter { signatures[$0.dateKey] != "\(style.rawValue)|\($0.signature)" && $0.hasAnyData }
        guard !todo.isEmpty else { return }
        let results = await Task.detached(priority: .utility) { () -> [(String, String, UIImage)] in
            todo.map { record in
                let image = RingThumbnailStore.shared.thumbnail(styleKey: style.rawValue, slices: record, style: style)
                return (record.dateKey, "\(style.rawValue)|\(record.signature)", image)
            }
        }.value
        for (key, signature, image) in results {
            images[key] = image
            signatures[key] = signature
        }
    }
}
