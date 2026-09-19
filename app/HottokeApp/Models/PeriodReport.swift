import Foundation
import CoreGraphics

/// 積算・レポートの期間。
enum RingPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "今日"
        case .week: return "1週間"
        case .month: return "1ヶ月"
        }
    }

    /// 期間の日数（今日を含む）。今日は1。
    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

/// 振り返りレポートの中身（期間の合計・活動別の時間・最も活発だった日と時間帯）。描画から切り離した純粋な集計。
struct PeriodReport: Equatable {
    let period: RingPeriod
    /// 期間の最初の日・最後の日（"yyyy-MM-dd"）。
    let startKey: String
    let endKey: String
    /// 期間内に保存があった日数。
    let savedDays: Int
    let totalSteps: Int
    /// 活動の種類ごとの合計分数。
    let minutesByKind: [ActivityKind: Double]
    let busiestDayKey: String?
    let busiestDaySteps: Int
    /// 歩数がもっとも多かった時間帯（0〜23時台）と、その期間の合計歩数。
    let busiestHour: Int?
    let busiestHourSteps: Int

    var averageStepsPerSavedDay: Int { savedDays > 0 ? totalSteps / savedDays : 0 }

    func minutes(_ kind: ActivityKind) -> Double { minutesByKind[kind] ?? 0 }

    /// 期間（今日を含む直近`period.days`日）に含まれる記録から集計する。
    static func make(records: [DailyRingSlices], period: RingPeriod, now: Date, calendar: Calendar = .current) -> PeriodReport {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: today) ?? today
        let startKey = DailyRingSlices.dateKey(for: start, calendar: calendar)
        let endKey = DailyRingSlices.dateKey(for: today, calendar: calendar)
        let inRange = records.filter { $0.dateKey >= startKey && $0.dateKey <= endKey && $0.hasAnyData }

        var minutes: [ActivityKind: Double] = [:]
        var stepsByHour = [Int](repeating: 0, count: 24)
        var busiestDay: (key: String, steps: Int)?
        var total = 0
        for record in inRange {
            for kind in DailyRingLayout.kindOrder { minutes[kind, default: 0] += record.minutes(kind) }
            for (hour, steps) in record.hourlySteps.enumerated() where hour < 24 { stepsByHour[hour] += steps }
            total += record.totalSteps
            if busiestDay == nil || record.totalSteps > busiestDay!.steps {
                busiestDay = (record.dateKey, record.totalSteps)
            }
        }
        var busiestHour: Int?
        var busiestHourSteps = 0
        for (hour, steps) in stepsByHour.enumerated() where steps > busiestHourSteps {
            busiestHour = hour
            busiestHourSteps = steps
        }
        return PeriodReport(
            period: period, startKey: startKey, endKey: endKey, savedDays: inRange.count,
            totalSteps: total, minutesByKind: minutes,
            busiestDayKey: (busiestDay?.steps ?? 0) > 0 ? busiestDay?.key : nil,
            busiestDaySteps: busiestDay?.steps ?? 0,
            busiestHour: busiestHour, busiestHourSteps: busiestHourSteps
        )
    }
}

/// 画像の書き出しサイズ。
enum RingExportSize: String, CaseIterable, Identifiable {
    case standard
    case high
    case wallpaper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "標準（1080px）"
        case .high: return "高解像度（2160px）"
        case .wallpaper: return "壁紙（画面の比率）"
        }
    }

    /// プロ機能か（標準は常に使える）。
    var requiresPro: Bool { self != .standard }

    /// 書き出すキャンバスの大きさ（ピクセル）。`screenPixels`は端末の画面のピクセル数（壁紙のとき使う）。
    func canvas(screenPixels: CGSize) -> CGSize {
        switch self {
        case .standard: return CGSize(width: 1080, height: 1080)
        case .high: return CGSize(width: 2160, height: 2160)
        case .wallpaper:
            let w = min(screenPixels.width, screenPixels.height)
            let h = max(screenPixels.width, screenPixels.height)
            guard w > 0, h > 0 else { return CGSize(width: 1179, height: 2556) }
            return CGSize(width: w.rounded(), height: h.rounded())
        }
    }
}
