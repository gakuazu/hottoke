import Foundation

/// 模様の描画方式（数学模様9スタイル）。
///
/// これまでの「ガラス片を敷き詰める」方式（GlassShard/KaleidoscopeShapeGenerator）は
/// 実機での見た目の不満（ダサい・キラキラしない）を受けて廃止し、ブラウザ上のプロトタイプ
/// （数式カレイドスコープ）で何度も調整してオーナー承認を得た「数学模様」に置き換える。
/// 各ケースの描画本体はKaleidoscopeRenderer.swiftのrenderTiling/renderSpirograph/
/// renderWaves/renderFractal/renderVoronoi/renderLissajous/renderTruchet/renderMoire/
/// renderFlowerに、プロトタイプのCanvas 2D実装を忠実に移植したもの。
///
/// 【2026-08-30追記】当初の4スタイル（tiling/spirograph/waves/fractal）に加えて、将来の
/// 課金要素（無料スタイル＋追加スタイルは課金で解放）の土台として5スタイル
/// （voronoi/lissajous/truchet/moire/flower）を追加した。新しい5つは`PatternStyle.style(for:)`
/// による活動種別からの自動選択の対象には含めず、手動モードでの選択専用とする。
/// `isLocked`はまだ実際の課金ロジックとは結び付いておらず、UIに鍵アイコンを出して
/// タップしても選択できないようにする「土台」のみ（KaleidoscopePalette.isLockedと同じ考え方）。
enum PatternStyle: String, CaseIterable, Equatable, Codable, Identifiable {
    case tiling
    case spirograph
    case waves
    case fractal
    case voronoi
    case lissajous
    case truchet
    case moire
    case flower

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiling: return "幾何学タイル"
        case .spirograph: return "スピログラフ"
        case .waves: return "波の干渉"
        case .fractal: return "フラクタル分岐"
        case .voronoi: return "ひび割れ"
        case .lissajous: return "リサージュ"
        case .truchet: return "トゥルーシェ"
        case .moire: return "モアレ格子"
        case .flower: return "花模様"
        }
    }

    /// 手動モード画面のスタイル選択スウォッチ用の短い表示名（狭いスペースでも折り返さないよう）。
    var shortLabel: String {
        switch self {
        case .tiling: return "タイル"
        case .spirograph: return "スピロ"
        case .waves: return "波"
        case .fractal: return "分岐"
        case .voronoi: return "ひび"
        case .lissajous: return "曲線"
        case .truchet: return "円弧"
        case .moire: return "モアレ"
        case .flower: return "花"
        }
    }

    /// 手動モード画面のスタイル選択スウォッチに使うSF Symbol。
    var iconName: String {
        switch self {
        case .tiling: return "square.grid.3x3.fill"
        case .spirograph: return "atom"
        case .waves: return "water.waves"
        case .fractal: return "tree.fill"
        case .voronoi: return "bolt.fill"
        case .lissajous: return "infinity"
        case .truchet: return "puzzlepiece.fill"
        case .moire: return "line.3.crossed.swirl.circle.fill"
        case .flower: return "camera.macro"
        }
    }

    /// 「今日の模様」で、このスタイルがなぜ選ばれたのかをひと目で分かるように添えるひと言。
    /// 「主な活動: ○○ → ××の模様」という1行だけでは対応関係が伝わりにくいという
    /// 実機フィードバックを受けて追加した。新しい5スタイルは自動選択の対象外（手動選択専用）
    /// だが、手動モードでも一言添えられるよう同様に用意する。
    var rationale: String {
        switch self {
        case .tiling: return "規則正しく歩いた1日を、整然と並ぶ幾何学模様で表現"
        case .spirograph: return "自転車で回転運動をした1日を、歯車のように巻く曲線で表現"
        case .waves: return "静かに過ごした1日を、ゆったり重なる波の模様で表現"
        case .fractal: return "よく走った1日を、勢いよく枝分かれする模様で表現"
        case .voronoi: return "予測できない1日を、ひび割れるように広がる模様で表現"
        case .lissajous: return "リズムに乗った1日を、なめらかに交差する曲線の模様で表現"
        case .truchet: return "積み重ねた1日を、タイルが連なるような模様で表現"
        case .moire: return "静と動が重なった1日を、繊細に干渉する縞模様で表現"
        case .flower: return "彩り豊かな1日を、幾重にも咲く花模様で表現"
        }
    }

    /// 課金で解放する予定のスタイルかどうか（土台のみ。実際の解放ロジックは未実装）。
    /// 既存4スタイルは無料のまま。新しい5スタイルのうち3つ（truchet/moire/flower）を
    /// ロック対象の例として設定し、手動モード等のUIで鍵アイコン表示・選択不可にする。
    var isLocked: Bool {
        switch self {
        case .tiling, .spirograph, .waves, .fractal, .voronoi, .lissajous:
            return false
        case .truchet, .moire, .flower:
            return true
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
