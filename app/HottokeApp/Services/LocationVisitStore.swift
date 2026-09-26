import Foundation

/// 「GPS自動日記」用に、大きく場所が変わったときだけ記録した位置情報のサンプルを端末内に保存する。
/// `DailyHistoryStore`と同じパターン（配列をJSONにしてApplication Support配下の1ファイルに保存）。
/// 外部へは一切送信しない。プライバシーのため、一定期間より古いサンプルは自動で消す。
final class LocationVisitStore {
    static let shared = LocationVisitStore()

    /// 何日分の位置情報サンプルを保持するか。これより古いものは自動で消す。
    static let retentionDays = 14

    private(set) var samples: [LocationVisitSample]
    private let fileURL: URL

    /// `directory`を渡すとそこに保存する（テスト用）。省略時はApplication Support。
    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("location-visits.json")
        samples = Self.load(from: fileURL)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HottokeHistory", isDirectory: true)
    }

    /// サンプルを1件追加し、保持期間より古いものは削除してから保存する。
    func add(_ sample: LocationVisitSample, now: Date = Date(), calendar: Calendar = .current) {
        samples.append(sample)
        prune(now: now, calendar: calendar)
        persist()
    }

    /// 指定の日（0時〜24時）に含まれるサンプル。
    func samples(on day: Date, calendar: Calendar = .current) -> [LocationVisitSample] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return samples.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    /// 保持期間より古いサンプルを削除する。
    func prune(now: Date = Date(), calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: calendar.startOfDay(for: now)) else { return }
        samples.removeAll { $0.timestamp < cutoff }
    }

    /// 設定をオフにしたときなど、貯めていた位置情報をすべて消す（プライバシーのため）。
    func removeAll() {
        guard !samples.isEmpty else { return }
        samples = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [LocationVisitSample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LocationVisitSample].self, from: data)) ?? []
    }
}
