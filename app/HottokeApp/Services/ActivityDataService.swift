import CoreMotion
import Foundation

/// docs/02-spec.md 3.1節の手順どおり、CMMotionActivityManagerとCMPedometerから
/// 「その日0時〜現在時刻まで」の活動データを取得する。
///
/// 技術メモ: CMMotionActivityManagerはOS側が端末にアプリの有無に関わらず継続記録している
/// データを保持しているため、その日の朝からアプリを開いていなくても、起動した瞬間に
/// その日の朝〜現在までの履歴を遡って取得できる。
final class ActivityDataService {

    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    func fetchToday(includeHourlySteps: Bool = false) async -> DailyActivityData {
        await fetch(for: Date(), includeHourlySteps: includeHourlySteps)
    }

    /// 指定した日の0時〜（今日ならその時点の現在時刻まで、過去の日ならその日の24時まで）の
    /// 活動データを取得する。過去の日を渡した場合に「アーカイブ」機能から呼ばれる想定。
    ///
    /// 技術メモ（重要な制約）: CMMotionActivityManagerがOS側に保持している活動履歴は、
    /// 目安で数日〜1週間程度しか遡れない。保持期間より前の日を指定した場合はエラーにはならず、
    /// 単に空の活動区間・0の歩数が返ってくる（＝「静けさの模様」相当のデータになる）。
    /// 「その日のデータがもう端末に残っていないため今から作れない」という判定自体は、
    /// 呼び出し側（ArchivePatternStore.isGeneratable）が日付の新しさだけで簡易的に行う。
    ///
    /// `includeHourlySteps`がtrueのときだけ、1時間ごとの歩数（24回の歩数計クエリ）も取得する
    /// （「1日の輪」用。従来の画面は不要なので既定はfalseにして待ち時間を増やさない）。
    func fetch(for date: Date, includeHourlySteps: Bool = false) async -> DailyActivityData {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let now = Date()
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        // 対象日が今日なら現在時刻まで、過去の日ならその日の24時までを取得範囲とする。
        let end = min(endOfDay, now)

        let segments: [ActivitySegment]
        if CMMotionActivityManager.isActivityAvailable() {
            segments = await queryActivitySegments(from: startOfDay, to: end)
        } else {
            segments = []
        }

        let (steps, distance, floors) = await queryPedometerTotals(from: startOfDay, to: end)

        var hourly = Array(repeating: 0, count: 24)
        if includeHourlySteps {
            hourly = await queryHourlySteps(startOfDay: startOfDay, until: end, calendar: calendar)
        }

        return DailyActivityData(
            date: startOfDay,
            segments: segments,
            stepCount: steps,
            distanceMeters: distance,
            floorsAscended: floors,
            floorAscendTimes: [],
            hourlySteps: hourly
        )
    }

    /// 0時台〜23時台の1時間ごとの歩数。まだ来ていない時間帯は問い合わせず0のままにする。
    /// 端末が保持する歩数計の履歴は直近約7日分までで、それ以前の日は0が返る。
    /// （夏時間のある地域で1日が23/25時間の日は、時間の区切りが1時間ずれることがあるが日本では影響なし）
    private func queryHourlySteps(startOfDay: Date, until end: Date, calendar: Calendar) async -> [Int] {
        var result = Array(repeating: 0, count: 24)
        guard CMPedometer.isStepCountingAvailable() else { return result }
        for hour in 0..<24 {
            guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay),
                  let hourEnd = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay) else { continue }
            if hourStart >= end { break }
            result[hour] = await querySteps(from: hourStart, to: min(hourEnd, end))
        }
        return result
    }

    private func querySteps(from start: Date, to end: Date) async -> Int {
        await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                guard let data, error == nil else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: data.numberOfSteps.intValue)
            }
        }
    }

    private func queryActivitySegments(from start: Date, to end: Date) async -> [ActivitySegment] {
        await withCheckedContinuation { continuation in
            // CMMotionActivityManagerの実際のAPIは from:/to:/to:(queue)/withHandler: という
            // 珍しいラベルの並びになっている（docs/02-spec.md 3.1節記載どおり）。
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
                guard error == nil, let activities else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: Self.buildSegments(from: activities, startOfDay: start, now: end))
            }
        }
    }

    private func queryPedometerTotals(from start: Date, to end: Date) async -> (steps: Int, distance: Double, floors: Int) {
        await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                guard let data, error == nil else {
                    continuation.resume(returning: (0, 0, 0))
                    return
                }
                continuation.resume(returning: (
                    data.numberOfSteps.intValue,
                    data.distance?.doubleValue ?? 0,
                    data.floorsAscended?.intValue ?? 0
                ))
            }
        }
    }

    /// CMMotionActivityの配列（開始時刻の点列）から、開始〜終了を持つ区間の配列に変換する。
    private static func buildSegments(from activities: [CMMotionActivity], startOfDay: Date, now: Date) -> [ActivitySegment] {
        guard !activities.isEmpty else { return [] }
        let sorted = activities.sorted { $0.startDate < $1.startDate }
        var segments: [ActivitySegment] = []
        for (index, activity) in sorted.enumerated() {
            let start = max(activity.startDate, startOfDay)
            let end = index + 1 < sorted.count ? sorted[index + 1].startDate : now
            guard end > start else { continue }
            segments.append(ActivitySegment(start: start, end: end, kind: ActivityKind(activity: activity)))
        }
        return segments
    }
}
