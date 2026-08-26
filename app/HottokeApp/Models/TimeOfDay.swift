import Foundation

/// 時間帯の区分。docs/02-spec.md 3.3節「いつだったか→色パレットマッピング表」に対応。
enum TimeOfDay: String, CaseIterable, Equatable {
    case morning   // 〜10時: 淡いパステル
    case daytime   // 10-16時: 彩度高い青〜黄
    case evening   // 16-19時: 夕焼け調
    case night     // 19時〜: 藍〜紫の発光調

    static func of(hour: Int) -> TimeOfDay {
        switch hour {
        case 0..<10: return .morning
        case 10..<16: return .daytime
        case 16..<19: return .evening
        default: return .night
        }
    }

    var displayName: String {
        switch self {
        case .morning: return "朝"
        case .daytime: return "昼"
        case .evening: return "夕方"
        case .night: return "夜"
        }
    }

    /// 乱数シードのオフセットに使う安定した整数値。
    /// (Swiftの合成Hashableのhash値はプロセスごとに変わりうるため、あえて固定の対応表にしている)
    var stableIndex: UInt64 {
        switch self {
        case .morning: return 0
        case .daytime: return 1
        case .evening: return 2
        case .night: return 3
        }
    }
}
