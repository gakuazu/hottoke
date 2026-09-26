import XCTest
@testable import HottokeApp

/// 「ひとこと日記」（`DiaryNote`/`DiaryNoteStore`/`DiaryEmoji`）のテスト。docs/29-app1-diary-note-design.md参照。
final class DiaryNoteStoreTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hottoke-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - DiaryNote / DiaryEmoji

    func testDiaryNoteIsEmptyOnlyWhenBothTextAndEmojiAreMissing() {
        XCTAssertTrue(DiaryNote(text: "", emoji: nil).isEmpty)
        XCTAssertFalse(DiaryNote(text: "よい天気だった", emoji: nil).isEmpty)
        XCTAssertFalse(DiaryNote(text: "", emoji: "😊").isEmpty)
        XCTAssertFalse(DiaryNote(text: "散歩した", emoji: "🚶").isEmpty)
    }

    func testDiaryEmojiHas16DistinctCasesWithLabelsAndMatchingSymbol() {
        XCTAssertEqual(DiaryEmoji.allCases.count, 16, "docs/29 4章の16種類")
        let symbols = Set(DiaryEmoji.allCases.map { $0.symbol })
        XCTAssertEqual(symbols.count, 16, "絵文字が重複していない")
        for emoji in DiaryEmoji.allCases {
            XCTAssertFalse(emoji.label.isEmpty)
            XCTAssertEqual(emoji.symbol, emoji.rawValue)
            XCTAssertEqual(emoji.id, emoji.rawValue)
        }
    }

    // MARK: - DiaryNoteStore

    func testSaveAndReadBackTextAndEmoji() {
        let store = DiaryNoteStore(directory: tempDirectory())
        XCTAssertNil(store.note(for: date(18), calendar: calendar))

        store.save(text: "公園を散歩した", emoji: "🚶", for: date(18), calendar: calendar)
        let note = store.note(for: date(18), calendar: calendar)
        XCTAssertEqual(note?.text, "公園を散歩した")
        XCTAssertEqual(note?.emoji, "🚶")

        // 別の日には影響しない
        XCTAssertNil(store.note(for: date(19), calendar: calendar))
    }

    func testSaveTruncatesTextToMaxLength() {
        let store = DiaryNoteStore(directory: tempDirectory())
        let long = String(repeating: "あ", count: 100)
        store.save(text: long, emoji: nil, for: date(18), calendar: calendar)
        XCTAssertEqual(store.note(for: date(18), calendar: calendar)?.text.count, DiaryNote.maxTextLength)
    }

    func testSavingEmptyTextAndNoEmojiRemovesTheDay() {
        let store = DiaryNoteStore(directory: tempDirectory())
        store.save(text: "元気だった", emoji: "😊", for: date(18), calendar: calendar)
        XCTAssertNotNil(store.note(for: date(18), calendar: calendar))

        // テキストを消し、絵文字も外すと、その日の記録ごと消える(空のカードを残さない)。
        store.save(text: "", emoji: nil, for: date(18), calendar: calendar)
        XCTAssertNil(store.note(for: date(18), calendar: calendar))
    }

    func testOverwritingReplacesThePreviousNoteForThatDay() {
        let store = DiaryNoteStore(directory: tempDirectory())
        store.save(text: "最初のひとこと", emoji: "😴", for: date(18), calendar: calendar)
        store.save(text: "書き直した", emoji: "🎉", for: date(18), calendar: calendar)
        let note = store.note(for: date(18), calendar: calendar)
        XCTAssertEqual(note?.text, "書き直した")
        XCTAssertEqual(note?.emoji, "🎉")
    }

    func testPersistsAcrossStoreInstancesAtTheSameDirectory() {
        let dir = tempDirectory()
        let store = DiaryNoteStore(directory: dir)
        store.save(text: "また今度書き直せる", emoji: "☕", for: date(20), calendar: calendar)

        let reopened = DiaryNoteStore(directory: dir)
        let note = reopened.note(for: date(20), calendar: calendar)
        XCTAssertEqual(note?.text, "また今度書き直せる")
        XCTAssertEqual(note?.emoji, "☕")
    }

    /// テキストだけ、絵文字だけの保存もできる（どちらか片方だけでも記録として残る）。
    func testTextOnlyAndEmojiOnlyAreBothValidNotes() {
        let store = DiaryNoteStore(directory: tempDirectory())
        store.save(text: "絵文字なしのメモ", emoji: nil, for: date(18), calendar: calendar)
        XCTAssertEqual(store.note(for: date(18), calendar: calendar)?.text, "絵文字なしのメモ")
        XCTAssertNil(store.note(for: date(18), calendar: calendar)?.emoji)

        store.save(text: "", emoji: "🌧️", for: date(19), calendar: calendar)
        XCTAssertEqual(store.note(for: date(19), calendar: calendar)?.emoji, "🌧️")
        XCTAssertEqual(store.note(for: date(19), calendar: calendar)?.text, "")
    }
}
