import Foundation

/// 1つの活動区間（開始〜終了、活動種別）。docs/02-spec.md 3.1節参照。
struct ActivitySegment: Equatable {
    let start: Date
    let end: Date
    let kind: ActivityKind

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// その日1日分の活動データ（CMMotionActivityManager + CMPedometerから取得したものをまとめた形）。
struct DailyActivityData: Equatable {
    let date: Date // その日の0時（startOfDay）
    let segments: [ActivitySegment]
    let stepCount: Int
    let distanceMeters: Double
    let floorsAscended: Int
    let floorAscendTimes: [Date] // MVPでは未使用（将来、階段区間の正確なタイミングを扱う場合に使う）

    var totalActiveSeconds: TimeInterval {
        segments
            .filter { $0.kind != .stationary && $0.kind != .unknown }
            .reduce(0) { $0 + $1.duration }
    }

    /// もっとも合計時間が長かった「移動系」の活動種別（今日の模様画面の統計表示に使う）。
    var dominantMovingKind: ActivityKind? {
        let moving = segments.filter { $0.kind != .stationary && $0.kind != .unknown }
        guard !moving.isEmpty else { return nil }
        let totals = Dictionary(grouping: moving, by: { $0.kind })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        return totals.max(by: { $0.value < $1.value })?.key
    }

    static let empty = DailyActivityData(
        date: Date(),
        segments: [],
        stepCount: 0,
        distanceMeters: 0,
        floorsAscended: 0,
        floorAscendTimes: []
    )
}
