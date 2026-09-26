import Foundation

/// 「ひとこと日記」（docs/29-app1-diary-note-design.md）: 1日につき短いテキスト＋絵文字1個。
struct DiaryNote: Codable, Equatable {
    /// 上限文字数（docs/29 3章）。「ひとこと」なので短め。カードの高さが増えすぎない範囲の目安。
    static let maxTextLength = 40

    var text: String
    /// 選んだ絵文字（`DiaryEmoji`のいずれかの文字そのもの）。未選択はnil。
    var emoji: String?

    /// テキストも絵文字も空（＝書いていない）か。空のカードを保存しないための判定に使う。
    var isEmpty: Bool { text.isEmpty && emoji == nil }
}

/// 「ひとこと日記」で選べる標準絵文字16種（docs/29-app1-diary-note-design.md 4章）。
/// 新しい画像素材は使わず、標準絵文字のみを使う。
enum DiaryEmoji: String, CaseIterable, Identifiable {
    case happy = "😊"
    case fun = "😄"
    case relieved = "😌"
    case sad = "😢"
    case irritated = "😠"
    case tired = "😴"
    case meal = "🍽️"
    case rest = "☕"
    case exercise = "🏃"
    case walk = "🚶"
    case celebration = "🎉"
    case study = "📚"
    case shopping = "🛍️"
    case sunny = "☀️"
    case rainy = "🌧️"
    case loved = "❤️"

    var id: String { rawValue }
    /// 表示する絵文字そのもの（保存にもそのままこの文字列を使う）。
    var symbol: String { rawValue }

    var label: String {
        switch self {
        case .happy: return "うれしい"
        case .fun: return "たのしい"
        case .relieved: return "ほっとした"
        case .sad: return "かなしい"
        case .irritated: return "イライラ"
        case .tired: return "疲れた"
        case .meal: return "ごはん"
        case .rest: return "ひと休み"
        case .exercise: return "運動"
        case .walk: return "お散歩"
        case .celebration: return "お祝い"
        case .study: return "勉強・仕事"
        case .shopping: return "買い物"
        case .sunny: return "晴れ"
        case .rainy: return "雨"
        case .loved: return "大切な人と"
        }
    }
}
