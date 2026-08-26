import Foundation

/// 「今日の模様」の確定・永続化を管理する。
/// docs/02-spec.md 7章の決定事項: 1日1回だけ生成・確定する（同日中の再訪では再生成しない）。
struct TodaySummary: Codable, Equatable {
    let dateKey: String
    let stepCount: Int
    let distanceMeters: Double
    let floorsAscended: Int
    let activeMinutes: Int
    let dominantKindRaw: String?
    let videoFileName: String
}

@MainActor
final class TodayPatternStore: ObservableObject {
    @Published private(set) var summary: TodaySummary?
    @Published private(set) var videoURL: URL?
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?

    private let activityService = ActivityDataService()
    private let exporter = KaleidoscopeVideoExporter()

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var metadataURL: URL {
        documentsDirectory.appendingPathComponent("today-summary.json")
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// 今日すでに確定済みの模様があればそれを読み込み、なければ新しく生成する。
    func loadOrGenerateTodayIfNeeded() async {
        let key = dateKey(for: Date())

        if let existing = loadPersistedSummary(), existing.dateKey == key {
            let url = documentsDirectory.appendingPathComponent(existing.videoFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                summary = existing
                videoURL = url
                return
            }
        }

        await generateToday(dateKey: key)
    }

    private func generateToday(dateKey key: String) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let data = await activityService.fetchToday()
        let fileName = "today-\(key).mp4"
        let outputURL = documentsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try await exporter.exportDailyPattern(data: data, to: outputURL)
            let newSummary = TodaySummary(
                dateKey: key,
                stepCount: data.stepCount,
                distanceMeters: data.distanceMeters,
                floorsAscended: data.floorsAscended,
                activeMinutes: Int(data.totalActiveSeconds / 60),
                dominantKindRaw: data.dominantMovingKind?.rawValue,
                videoFileName: fileName
            )
            persist(summary: newSummary)
            summary = newSummary
            videoURL = outputURL
        } catch {
            errorMessage = "模様の生成に失敗しました: \(error.localizedDescription)"
        }
    }

    private func persist(summary: TodaySummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func loadPersistedSummary() -> TodaySummary? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(TodaySummary.self, from: data)
    }
}
