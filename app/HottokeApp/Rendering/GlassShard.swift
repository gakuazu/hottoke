import CoreGraphics

/// 「ガラス片」形状。docs/03b-visual-prototype-learnings.md
/// 「輪郭のはっきりしたガラス片形状（ひし形・鋭角三角形）を敷き詰める」に対応。
enum GlassShardShape {
    case diamond
    case triangle
}

/// 扇形（wedge）ローカル座標系（極座標）で表現した1つのガラス片。
/// radius/angleは正規化済み（radius: 0...1、angleは必ず [0, wedgeAngle) の範囲に収める）。
struct GlassShard {
    let radius: CGFloat
    let angle: CGFloat
    let size: CGFloat
    let rotation: CGFloat
    let colorIndex: Int
    let shape: GlassShardShape
    /// 生成時に1回だけ決める、個体ごとに異なる揺らぎの位相・強さ。
    /// 「回っているだけ」に見えないよう、各ガラス片が独立して呼吸するように動かすために使う。
    let wobblePhase: CGFloat
    let wobbleAmount: CGFloat
}

/// 中心から放射する光の筋。
struct LightRay {
    let angle: CGFloat
    let length: CGFloat
    let width: CGFloat
}

/// 小さな輝き。
struct Spark {
    let radius: CGFloat
    let angle: CGFloat
    let size: CGFloat
    /// 中心が白、外側がパレットの該当色に染まる放射グラデーションに使う色インデックス。
    let colorIndex: Int
    let wobblePhase: CGFloat
    let wobbleAmount: CGFloat
}

/// 扇形1つ分の模様データ。この1セットを対称数の回数だけ「スタンプ」して全体を作る。
struct WedgePattern {
    let wedgeAngle: CGFloat
    let facets: [GlassShard]
    let shards: [GlassShard]
    let rays: [LightRay]
    let sparks: [Spark]
}
