import CoreGraphics

/// 模様レンダリング1フレーム分のパラメータ。
/// 「今日の模様」動画の書き出しと、手動モードのライブプレビューの両方が同じ構造体を使う。
struct KaleidoscopeParameters: Equatable {
    var symmetryCount: Int = 8         // 対称数 n（扇形の数）
    var seed: UInt64 = 1                // 模様の形そのものを決める乱数シード
    var palette: KaleidoscopePalette = .daytime
    var rotation: Double = 0            // 全体の回転角（ラジアン）
    var pulsePhase: Double = 0.5        // 0...1（呼吸するような拡大縮小に使う）
    var deformationIntensity: Double = 0.4 // 0...1
    var rotationSpeed: Double = 0.15    // 参考値（実際の回転はrotationに事前計算して渡す）
    var shardDensity: Double = 0.6      // 0...1（ガラス片の密度）
    var noiseAmount: Double = 0.05      // 0...1（将来のゆらぎ表現用に予約、MVPでは未使用）
    var flowOffset: CGVector = .zero    // 手動モードの「振る」操作による一時的な模様全体のズレ
    var radialBurst: Double = 0         // 0...1（階段を上った量に応じた放射状の演出）
}
