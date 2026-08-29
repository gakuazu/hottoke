import CoreGraphics

/// 模様レンダリング1フレーム分のパラメータ。
/// 「今日の模様」動画の書き出しと、手動モードのライブプレビューの両方が同じ構造体を使う。
struct KaleidoscopeParameters: Equatable {
    var symmetryCount: Int = 8         // 対称数 n（扇形の数）
    var seed: UInt64 = 1                // 模様の形そのものを決める乱数シード（現状は未使用のGlassShard方式向けに残置）
    var palette: KaleidoscopePalette = .daytime
    var rotation: Double = 0            // 全体の回転角（ラジアン）
    var pulsePhase: Double = 0.5        // 0...1（階段を上った量の放射演出のリング半径に使う。KaleidoscopeRenderer参照）
    var deformationIntensity: Double = 0.4 // 0...1（未使用のGlassShard方式向けに残置。新方式では使わない）
    var rotationSpeed: Double = 0.15    // 参考値（実際の回転はrotationに事前計算して渡す）
    var shardDensity: Double = 0.6      // 0...1（未使用のGlassShard方式向けに残置。新方式では使わない）
    var noiseAmount: Double = 0.05      // 0...1（未使用のGlassShard方式向けに残置。新方式では使わない）
    var flowOffset: CGVector = .zero    // 手動モードの「振る」操作による一時的な模様全体のズレ
    var radialBurst: Double = 0         // 0...1（階段を上った量に応じた放射状の演出）
    var time: Double = 0                // 経過秒数。模様の動的な揺らぎ（呼吸・きらめき等）すべての時間軸に使う

    // MARK: - 数学模様4スタイル（docs/02-spec.md参照。ガラス片方式から置き換え）

    var patternStyle: PatternStyle = .waves // 幾何学タイル/スピログラフ/波の干渉/フラクタル分岐
    var detail: Double = 0.5                // 0...1（密度・複雑さの基準値。KaleidoscopeRenderer内でtimeを使い緩やかに揺らされた上で使われる）
}
