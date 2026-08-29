import Foundation

/// 過去の1日ぶんの模様の記録（アーカイブ画面のカレンダーに表示する内容）。
/// TodayPatternStoreのTodaySummaryと似た構造だが、アーカイブは「今日」以外の
/// 複数日を同時に扱うため、日付ごとに辞書で管理する（archive-index.json）。
struct ArchiveEntry: Codable, Equatable, Identifiable {
    let dateKey: String
    let stepCount: Int
    let distanceMeters: Double
    let floorsAscended: Int
    let activeMinutes: Int
    let dominantKindRaw: String?
    let videoFileName: String
    let patternStyleRaw: String

    var id: String { dateKey }
}

/// 「過去の模様アーカイブ」機能（docs/02-spec.md 2章 #6）の永続化・生成ロジック。
///
/// 「今日」の模様は引き続きTodayPatternStoreが管理する。このストアは「今日」以外の
/// 過去の日付ごとの模様一覧を管理するが、「今日」についてはTodayPatternStoreが書き出す
/// today-summary.json / 動画ファイルをそのまま読み取って流用する（entry(for:)参照）。
/// 動画ファイルを二重に持つ無駄を避けるための工夫で、過度な統合はしていない。
@MainActor
final class ArchivePatternStore: ObservableObject {
    @Published private(set) var entriesByDateKey: [String: ArchiveEntry] = [:]
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?

    private let activityService = ActivityDataService()
    private let exporter = KaleidoscopeVideoExporter()

    /// CMMotionActivityManagerがOS側に保持している活動履歴の目安の保持期間（日数）。
    /// docs/02-spec.mdおよびオーナーへの説明どおり「数日〜1週間程度」を前提に、
    /// 安全側に見て7日とする。これより古い日で未生成のものは「今からはもう作れない」と案内する。
    static let retentionDays = 7

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var indexURL: URL {
        documentsDirectory.appendingPathComponent("archive-index.json")
    }

    private var todaySummaryURL: URL {
        documentsDirectory.appendingPathComponent("today-summary.json")
    }

    init() {
        entriesByDateKey = Self.loadIndex(at: indexURL)
    }

    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// 指定した日にすでに生成済みの模様があれば返す。「今日」については、
    /// TodayPatternStoreが保存したtoday-summary.jsonを直接読み取って代用する
    /// （TodayView側で今日の模様が生成済みなら、ここでもそのまま一覧に出せるようにするため）。
    func entry(for date: Date) -> ArchiveEntry? {
        let key = Self.dateKey(for: date)
        if key == Self.dateKey(for: Date()), let todaySummary = loadTodaySummary() {
            return ArchiveEntry(
                dateKey: key,
                stepCount: todaySummary.stepCount,
                distanceMeters: todaySummary.distanceMeters,
                floorsAscended: todaySummary.floorsAscended,
                activeMinutes: todaySummary.activeMinutes,
                dominantKindRaw: todaySummary.dominantKindRaw,
                videoFileName: todaySummary.videoFileName,
                patternStyleRaw: todaySummary.patternStyleRaw
            )
        }
        return entriesByDateKey[key]
    }

    func videoURL(for entry: ArchiveEntry) -> URL {
        documentsDirectory.appendingPathComponent(entry.videoFileName)
    }

    /// 指定した日が「これから新しく生成できる」範囲内かどうか（未来ではなく、かつOSの活動履歴の
    /// 保持期間内）。すでに生成済みかどうかはこの判定に含まない（呼び出し側でentry(for:)と
    /// 組み合わせて使う）。
    func isGeneratable(date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        guard target <= today else { return false } // 未来の日は不可
        guard let oldestAllowed = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: today) else {
            return false
        }
        return target >= oldestAllowed
    }

    /// 指定した日のデータを取得して動画を生成し、アーカイブに保存する。
    /// 「今日」を指定した場合でも、TodayPatternStoreとは別にアーカイブ専用の動画ファイルを
    /// 新しく作る（TodayPatternStoreが管理するファイルには一切手を触れない）。
    func generate(for date: Date) async throws {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let key = Self.dateKey(for: date)
        let data = await activityService.fetch(for: date)
        let style = data.dominantMovingKind.map(PatternStyle.style(for:)) ?? .waves
        let fileName = "archive-\(key)-\(style.rawValue).mp4"
        let outputURL = documentsDirectory.appendingPathComponent(fileName)

        do {
            try await exporter.exportDailyPattern(data: data, to: outputURL)
        } catch {
            errorMessage = "模様の生成に失敗しました: \(error.localizedDescription)"
            throw error
        }

        let entry = ArchiveEntry(
            dateKey: key,
            stepCount: data.stepCount,
            distanceMeters: data.distanceMeters,
            floorsAscended: data.floorsAscended,
            activeMinutes: Int(data.totalActiveSeconds / 60),
            dominantKindRaw: data.dominantMovingKind?.rawValue,
            videoFileName: fileName,
            patternStyleRaw: style.rawValue
        )
        entriesByDateKey[key] = entry
        persistIndex()
    }

    private func loadTodaySummary() -> TodaySummary? {
        guard let data = try? Data(contentsOf: todaySummaryURL) else { return nil }
        return try? JSONDecoder().decode(TodaySummary.self, from: data)
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entriesByDateKey) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func loadIndex(at url: URL) -> [String: ArchiveEntry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ArchiveEntry].self, from: data)) ?? [:]
    }
}
