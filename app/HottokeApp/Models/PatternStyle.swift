import Foundation

/// 模様の描画方式（数学模様4スタイル）。
///
/// これまでの「ガラス片を敷き詰める」方式（GlassShard/KaleidoscopeShapeGenerator）は
/// 実機での見た目の不満（ダサい・キラキラしない）を受けて廃止し、ブラウザ上のプロトタイプ
/// （数式カレイドスコープ）で何度も調整してオーナー承認を得た「数学模様」4種類に置き換える。
/// 各ケースの描画本体はKaleidoscopeRenderer.swiftのrenderTiling/renderSpirograph/
/// renderWaves/renderFractalに、プロトタイプのCanvas 2D実装を忠実に移植したもの。
enum PatternStyle: String, CaseIterable, Equatable, Codable, Identifiable {
    case tiling
    case spirograph
    case waves
    case fractal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiling: return "幾何学タイル"
        case .spirograph: return "スピログラフ"
        case .waves: return "波の干渉"
        case .fractal: return "フラクタル分岐"
        }
    }

    /// 手動モード画面のスタイル選択スウォッチ用の短い表示名（狭いスペースでも折り返さないよう）。
    var shortLabel: String {
        switch self {
        case .tiling: return "タイル"
        case .spirograph: return "スピロ"
        case .waves: return "波"
        case .fractal: return "分岐"
        }
    }

    /// 手動モード画面のスタイル選択スウォッチに使うSF Symbol。
    var iconName: String {
        switch self {
        case .tiling: return "square.grid.3x3.fill"
        case .spirograph: return "atom"
        case .waves: return "water.waves"
        case .fractal: return "tree.fill"
        }
    }
}

/// 活動種別 → 数学模様スタイルのマッピング。オーナーとの相談で決めた対応（docs/02-spec.md参照）:
///   stationary, unknown, automotive → waves（穏やか・滑らかな動きに合う）
///   walking                        → tiling（規則的な歩行リズムに合う）
///   cycling                        → spirograph（歯車のような回転運動に合う）
///   running                        → fractal（激しく分岐するエネルギーに合う）
extension PatternStyle {
    static func style(for kind: ActivityKind) -> PatternStyle {
        switch kind {
        case .stationary, .unknown, .automotive:
            return .waves
        case .walking:
            return .tiling
        case .cycling:
            return .spirograph
        case .running:
            return .fractal
        }
    }
}
