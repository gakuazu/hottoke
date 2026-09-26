import Foundation

/// 「GPS自動日記」（その日いた場所から、ひとこと日記のデフォルトの下書きを作る）の設定。
/// `ProAccess`と同じパターン（設定画面のトグル1つ、既定はオン）。
enum LocationDiarySettings {
    static let storageKey = "locationDiaryEnabled"
    /// 既定はオン。オフにすると位置情報の取得自体を止め、貯めていた位置情報も消す。
    static let defaultEnabled = true

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultEnabled
    }
}

/// 「写真リンク」（その日撮った写真のサムネイルを、ひとこと日記のそばに表示する）の設定。
enum DiaryPhotoLinkSettings {
    static let storageKey = "diaryPhotoLinkEnabled"
    /// 既定はオン。
    static let defaultEnabled = true

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultEnabled
    }
}
