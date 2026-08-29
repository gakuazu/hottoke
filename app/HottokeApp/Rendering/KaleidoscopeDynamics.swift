import Foundation

/// プロトタイプ（数式カレイドスコープ）の`renderWedge`/`stampAll`/`renderFrame`にあった
/// 「単に回転するだけでなく、密度・回転速度・拡大縮小がゆっくり呼吸するように揺らぐ」動的
/// パラメータの仕組みを移植したもの。手動モードのライブプレビュー（ManualModeView）と
/// 「今日の模様」動画書き出し（KaleidoscopeVideoExporter）の両方から使う共通ロジック。
///
/// 設計上の注意: JS版はrequestAnimationFrameのループの中で「前フレームの値 + 今回の増分」を
/// 毎フレーム積算していく作り（Euler積分）だが、このアプリのレンダリングは
/// 「経過時間(time)から毎回ゼロベースで計算する純関数」を基本方針にしている
/// （KaleidoscopeCanvasView/TodayViewの既存コメント参照: TimelineViewはAnimatableではないため
/// フレーム欠けが起きても自己修復するよう、経過時間から都度計算する設計にしている）。
/// そのため回転角(speedDrift)は「瞬間の角速度の式をtimeで解析的に積分した閉じた式」として
/// 実装し、他は元々瞬間値の式なのでそのまま移植する。
enum KaleidoscopeDynamics {

    /// 密度・複雑さ(detail)を基準値を中心にゆっくり呼吸させる（プロトタイプrenderWedgeの
    /// detailDrift）。周波数の異なる2つのsinを重ねることで単純な繰り返しに見えないようにする。
    static func effectiveDetail(base: Double, time: Double) -> Double {
        let detailDrift = 0.40 * sin(time * 0.42 + 0.6) + 0.14 * sin(time * 1.15 + 2.0)
        return min(1, max(0, base + detailDrift))
    }

    /// 模様全体のゆっくりとしたズームイン・アウト（プロトタイプstampAllのbreathEnvelope/pulse）。
    /// KaleidoscopeRenderer側で全体のスケール係数としてそのまま乗算する。
    static func zoomPulse(time: Double) -> Double {
        let breathEnvelope = 0.5 + 0.5 * sin(time * 0.29 + 2.1)
        return 1
            + (0.03 + 0.15 * breathEnvelope) * sin(time * 1.3)
            + 0.10 * breathEnvelope
            + 0.045 * sin(time * 0.6 + 1.3)
    }

    /// 「ただ等速で回る」感じから抜け出すための、加速・減速（たまに一瞬逆回転もする）回転角。
    /// プロトタイプrenderFrameのspeedDriftは瞬間の角速度への倍率で、JS版はdt刻みで積算する。
    /// ここでは同じ倍率の式を時間で解析的に積分した閉じた式にして、経過時間だけから
    /// 毎回ゼロベースで正しい回転角が求まるようにしている。speedDriftの長期平均は1.1倍になる
    /// ため、その平均で正規化し、`angularSpeed`(ラジアン/秒)を基準速度として素直に使えるようにした。
    static func organicRotationAngle(elapsed: Double, angularSpeed: Double) -> Double {
        func speedDriftIntegral(_ t: Double) -> Double {
            1.1 * t
                - (1.3 / 0.22) * cos(0.22 * t)
                - (0.55 / 0.62) * cos(0.62 * t + 1.1)
                - (0.3 / 1.4) * cos(1.4 * t + 0.4)
        }
        let normalized = (speedDriftIntegral(elapsed) - speedDriftIntegral(0)) / 1.1
        return angularSpeed * normalized
    }
}
