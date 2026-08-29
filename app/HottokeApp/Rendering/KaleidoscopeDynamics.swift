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
    ///
    /// 注意: この閉じた式は「`angularSpeed`が動画（あるいはプレビュー）を通してずっと一定」で
    /// あることを前提にした解析的積分であり、`angularSpeed`が時間とともに変化するケースにそのまま
    /// 使うと、`angularSpeed`が変わった瞬間に正規化係数ごと過去の角度全体がスケールし直されてしまい、
    /// 隣接フレーム間で回転角が不連続にジャンプする（実機フィードバックで判明した「今日の模様」
    /// 動画の後半がガタガタする不具合の原因）。手動モードのライブプレビュー（ManualModeView）は
    /// `angularSpeed`がユーザー操作によるスライダー値でフレームごとに急変しないため、この関数を
    /// そのまま使い続けて問題ない。一方、「今日の模様」動画書き出し（KaleidoscopeVideoExporter）は
    /// 活動区間が切り替わるたびにフレーム単位で`angularSpeed`（＝`ActivityStyle.rotationSpeed`）が
    /// 変化しうるため、この関数ではなく`speedDriftMultiplier(elapsed:)`を使ってフレームごとに
    /// 角度を数値積算する方式に変更した（KaleidoscopeVideoExporter参照）。
    static func organicRotationAngle(elapsed: Double, angularSpeed: Double) -> Double {
        let normalized = (speedDriftIntegral(elapsed) - speedDriftIntegral(0)) / 1.1
        return angularSpeed * normalized
    }

    /// `organicRotationAngle`の閉じた式が前提にしている「瞬間の角速度への倍率」そのもの
    /// （`speedDriftIntegral`の導関数を、長期平均1.1で正規化したもの。長期平均は1になる）。
    /// `angularSpeed`が時間とともに変化する場合は、この倍率を使って
    /// `rotation[i] = rotation[i-1] + angularSpeed(i) * speedDriftMultiplier(elapsed[i]) * dt`
    /// のようにフレームごとに数値積算することで、`organicRotationAngle`と同じ「呼吸するような
    /// 加速・減速」の質感を保ったまま、`angularSpeed`の変化にも連続的に追従できる
    /// （KaleidoscopeVideoExporter参照）。
    static func speedDriftMultiplier(elapsed: Double) -> Double {
        let raw = 1.1
            + 1.3 * sin(0.22 * elapsed)
            + 0.55 * sin(0.62 * elapsed + 1.1)
            + 0.3 * sin(1.4 * elapsed + 0.4)
        return raw / 1.1
    }

    private static func speedDriftIntegral(_ t: Double) -> Double {
        1.1 * t
            - (1.3 / 0.22) * cos(0.22 * t)
            - (0.55 / 0.62) * cos(0.62 * t + 1.1)
            - (0.3 / 1.4) * cos(1.4 * t + 0.4)
    }
}
