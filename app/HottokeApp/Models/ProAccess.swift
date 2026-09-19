import Foundation

/// プロモードの機能。
enum ProFeature: String, CaseIterable, Identifiable {
    /// 1週間・1ヶ月の積算リング
    case aggregation
    /// 今日と普段を重ねて比べる
    case comparison
    /// 振り返りレポート
    case report
    /// 高解像度・壁紙サイズでの書き出し
    case highQualityExport
    /// 配色テーマの切り替え
    case colorThemes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aggregation: return "積算（1週間・1ヶ月）"
        case .comparison: return "今日と普段の比較"
        case .report: return "振り返りレポート"
        case .highQualityExport: return "高解像度・壁紙の書き出し"
        case .colorThemes: return "配色テーマ"
        }
    }

    var summary: String {
        switch self {
        case .aggregation: return "複数日の活動を1枚の輪に重ねて、期間の傾向を見ます。"
        case .comparison: return "普段の形を淡い点で背後に重ね、今日との違いを見ます。"
        case .report: return "期間の積算の輪と、合計歩数・活動の時間・最も活発だった日と時間帯を1枚にまとめます。"
        case .highQualityExport: return "2160pxの高解像度、または端末の画面に合わせた壁紙サイズで保存します。"
        case .colorThemes: return "夜空・オーロラ・夏祭り・月光の配色に切り替えます。"
        }
    }
}

/// プロモードの利用可否。
///
/// いまは課金の仕組みを入れていないので、「プロモード」のオン・オフを1つのスイッチ（設定画面のトグル）で
/// 切り替える。このビルド（家族用）の既定はオン。将来StoreKitで課金するときは、`isUnlocked(_:enabled:)`の
/// 判定を購入状態に置き換えるだけで、各画面は変えずに済む（各画面は必ずここを通して判定する）。
enum ProAccess {
    /// 設定を保存するキー（@AppStorageで使う）。
    static let storageKey = "proModeEnabled"
    /// このビルドの既定。家族用のビルドなので常にオン。
    static let defaultEnabled = true

    /// 保存されている設定を読む（未設定なら既定）。
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultEnabled
    }

    /// その機能が使えるか。`enabled`は設定のトグルの値（画面側は@AppStorageで持つ）。
    /// 将来: ここで購入状態（StoreKitのEntitlement）と組み合わせる。
    static func isUnlocked(_ feature: ProFeature, enabled: Bool) -> Bool {
        enabled
    }

    /// ロックされているときに出す説明。
    static func lockedMessage(for feature: ProFeature) -> String {
        "「\(feature.displayName)」はプロ機能です。設定でプロモードをオンにすると使えます。"
    }
}
