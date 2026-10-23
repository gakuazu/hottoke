import Foundation

/// 息(ふーっ)の簡易判定。マイクの音量(RMS)と低音域の割合を受け取って、息の強さ(0...1)を返す。
/// 周囲の騒音は「ゆっくり追従するノイズ床」として差し引き、一定時間続いたときだけ息とみなす。
struct BreathDetector {
    /// 0...1。大きいほど弱い息でも反応する
    var sensitivity: Double = 0.6
    /// 息とみなすのに必要な持続時間(秒)
    var minDuration: Double = 0.1
    /// 低音域の割合の下限（息は「ボッ」という低音寄りの雑音。高音寄りは除外）
    var minLowRatio: Double = 0.3

    private(set) var noiseFloor: Double = -1
    private(set) var sustained: Double = 0
    private(set) var intensity: Double = 0
    private(set) var isBreathing: Bool = false

    /// 感度から「ノイズ床より何だけ大きければ息か」を求める
    static func margin(forSensitivity s: Double) -> Double {
        let c = min(1, max(0, s))
        return 0.05 + (0.004 - 0.05) * c
    }

    @discardableResult
    mutating func feed(rms: Double, lowRatio: Double, dt: Double) -> Double {
        if noiseFloor < 0 { noiseFloor = rms }
        let margin = Self.margin(forSensitivity: sensitivity)
        let excess = rms - noiseFloor - margin
        let candidate = excess > 0 && lowRatio >= minLowRatio

        if candidate {
            sustained += dt
        } else {
            sustained = 0
            // 息でないときだけ騒音レベルにゆっくり追従
            let k = min(1, dt * 0.6)
            noiseFloor += (rms - noiseFloor) * k
        }

        isBreathing = candidate && sustained >= minDuration
        let target = isBreathing ? min(1, max(0.15, excess / (margin * 4))) : 0
        // 立ち上がりは速く、立ち下がりはゆっくり
        let rate = target > intensity ? 12.0 : 4.0
        intensity += (target - intensity) * min(1, dt * rate)
        if intensity < 0.001 { intensity = 0 }
        return intensity
    }
}
