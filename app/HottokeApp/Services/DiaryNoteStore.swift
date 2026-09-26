import Foundation

/// 「ひとこと日記」（`DiaryNote`）を日付キーで端末内に保存する。
///
/// `DailyHistoryStore`（歩数・活動データ）と同じパターン（日付キーの辞書をJSONにして
/// Application Support配下の1ファイルに保存）だが、あえて別ファイルにしている。
/// 片方の仕組みに手を入れても、もう片方（歩数・活動の履歴）を壊すリスクを減らすため。
/// 外部へは送信しない。
final class DiaryNoteStore: ObservableObject {
    static let shared = DiaryNoteStore()

    @Published private(set) var notes: [String: DiaryNote]

    private let fileURL: URL

    /// `directory`を渡すとそこに保存する（テスト用）。省略時はApplication Support。
    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("diary-notes.json")
        notes = Self.load(from: fileURL)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HottokeHistory", isDirectory: true)
    }

    /// 指定の日の記録（なければnil）。
    func note(for date: Date, calendar: Calendar = .current) -> DiaryNote? {
        notes[DailyRingSlices.dateKey(for: date, calendar: calendar)]
    }

    /// 指定の日の記録を保存する。テキストは`DiaryNote.maxTextLength`で切り詰める。
    /// テキスト・絵文字とも空になったら、その日の記録ごと削除する（空のカードを残さない）。
    func save(text: String, emoji: String?, for date: Date, calendar: Calendar = .current) {
        let key = DailyRingSlices.dateKey(for: date, calendar: calendar)
        let trimmed = String(text.prefix(DiaryNote.maxTextLength))
        let note = DiaryNote(text: trimmed, emoji: emoji)
        if note.isEmpty {
            guard notes[key] != nil else { return }
            notes.removeValue(forKey: key)
        } else {
            guard notes[key] != note else { return }
            notes[key] = note
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: DiaryNote] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: DiaryNote].self, from: data)) ?? [:]
    }
}
