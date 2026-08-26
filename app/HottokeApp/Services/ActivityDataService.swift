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

    func fetchToday() async -> DailyActivityData {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let segments: [ActivitySegment]
        if CMMotionActivityManager.isActivityAvailable() {
            segments = await queryActivitySegments(from: startOfDay, to: now)
        } else {
            segments = []
        }

        let (steps, distance, floors) = await queryPedometerTotals(from: startOfDay, to: now)

        return DailyActivityData(
            date: startOfDay,
            segments: segments,
            stepCount: steps,
            distanceMeters: distance,
            floorsAscended: floors,
            floorAscendTimes: []
        )
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
