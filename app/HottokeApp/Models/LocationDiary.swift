import Foundation

/// 「GPS自動日記」で記録する、位置情報の1サンプル（大きく場所が変わったときだけ記録される）。
struct LocationVisitSample: Codable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
}

/// 「GPS自動日記」の判定ロジック（CoreLocation/CLGeocoderを使わない、テスト可能な純粋関数）。
///
/// 考え方:
///  ・`CLLocationManager.startMonitoringSignificantLocationChanges()`は、およそ500m以上
///    大きく場所が変わったときだけ通知される省電力な方式。そのため1日の記録は数件程度の
///    「点」になる。連続する点の間隔を「その場所に居た時間」とみなして、1日のうちで
///    合計の滞在時間が最も長かった場所を、その日いた場所とみなす。
///  ・自宅と思われる場所（全期間でもっとも頻繁に現れる場所）にいた日は、地名を出さずに
///    「自宅で過ごした」という控えめな表現にする（自宅の地名をひとこと日記に書き残さないため）。
enum LocationDiaryAnalyzer {
    /// 緯度経度を、およそ500m四方の格子に丸めたキー（同じ場所とみなす単位）。
    static func gridKey(latitude: Double, longitude: Double) -> String {
        let step = 0.005 // およそ550m（緯度方向の目安）。
        let latCell = Int((latitude / step).rounded(.down))
        let lonCell = Int((longitude / step).rounded(.down))
        return "\(latCell),\(lonCell)"
    }

    /// 全期間のサンプルのうち、もっとも頻繁に現れる格子（＝自宅と推定する場所）。1件もなければnil。
    static func homeGridKey(samples: [LocationVisitSample]) -> String? {
        guard !samples.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for sample in samples {
            counts[gridKey(latitude: sample.latitude, longitude: sample.longitude), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// その日（`dayStart`〜`dayEnd`）にもっとも長く滞在したとみられる場所。
    /// 各サンプルの「滞在時間」は、次のサンプル（なければその日の終わり）までの時間差とみなす。
    /// 該当するサンプルが1件もなければnil。
    static func longestStay(daySamples: [LocationVisitSample], dayStart: Date, dayEnd: Date) -> (gridKey: String, latitude: Double, longitude: Double)? {
        let sorted = daySamples.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        var durations: [String: TimeInterval] = [:]
        var coordinateSums: [String: (lat: Double, lon: Double, count: Int)] = [:]
        for (index, sample) in sorted.enumerated() {
            guard sample.timestamp >= dayStart, sample.timestamp < dayEnd else { continue }
            let key = gridKey(latitude: sample.latitude, longitude: sample.longitude)
            let periodEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : dayEnd
            let duration = min(periodEnd, dayEnd).timeIntervalSince(sample.timestamp)
            guard duration > 0 else { continue }
            durations[key, default: 0] += duration
            var sum = coordinateSums[key] ?? (0, 0, 0)
            sum.lat += sample.latitude
            sum.lon += sample.longitude
            sum.count += 1
            coordinateSums[key] = sum
        }
        guard let winnerKey = durations.max(by: { $0.value < $1.value })?.key,
              let sum = coordinateSums[winnerKey], sum.count > 0 else { return nil }
        return (winnerKey, sum.lat / Double(sum.count), sum.lon / Double(sum.count))
    }

    /// 逆ジオコーディング結果（`CLPlacemark`相当のフィールド）から、地名として使う文字列を選ぶ。
    /// 分からなければnil（無理に何かを表示しない）。
    static func placeName(subLocality: String?, locality: String?, name: String?, administrativeArea: String?) -> String? {
        for candidate in [subLocality, locality, name, administrativeArea] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    /// 地名（自宅でない場合）・自宅かどうかから、デフォルトの下書き文章を作る。
    /// 地名が分からず、自宅でもなければnil（空のままにする）。
    static func defaultText(placeName: String?, isHome: Bool) -> String? {
        if isHome { return "自宅で過ごした" }
        guard let placeName, !placeName.isEmpty else { return nil }
        return "\(placeName)にいた"
    }
}
