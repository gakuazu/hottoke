import CoreMotion
import CoreGraphics

/// 活動種別。docs/02-spec.md 3.2節「何をしていたか→模様の動き方マッピング表」に対応。
enum ActivityKind: String, CaseIterable, Equatable {
    case stationary
    case walking
    case running
    case automotive
    case cycling
    case unknown

    init(activity: CMMotionActivity) {
        if activity.running {
            self = .running
        } else if activity.cycling {
            self = .cycling
        } else if activity.walking {
            self = .walking
        } else if activity.automotive {
            self = .automotive
        } else if activity.stationary {
            self = .stationary
        } else {
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .stationary: return "静止"
        case .walking: return "歩行"
        case .running: return "走行"
        case .automotive: return "車移動"
        case .cycling: return "自転車"
        case .unknown: return "不明"
        }
    }
}

/// 活動種別 → 模様の動きパラメータへの変換。docs/02-spec.md 3.2節の表をそのまま数値化したもの。
struct ActivityStyle: Equatable {
    let rotationSpeed: Double          // ラジアン/秒の目安
    let deformationIntensity: Double   // 0...1
    let noiseAmount: Double            // 0...1（将来のゆらぎ表現用に予約）
    let flowBias: CGVector             // automotive(車移動)のスライド流れ方向
    let radialBurstBias: Double        // 将来の拡張用（現状は0固定）

    static func style(for kind: ActivityKind) -> ActivityStyle {
        switch kind {
        case .stationary:
            // ゆったり回転する瞑想的な模様
            return ActivityStyle(rotationSpeed: 0.06, deformationIntensity: 0.15, noiseAmount: 0.03, flowBias: .zero, radialBurstBias: 0)
        case .walking:
            // 歩行ケイデンスに合わせた一定リズムの拍動（MVPでは簡易的に中程度の周期回転で表現）
            return ActivityStyle(rotationSpeed: 0.18, deformationIntensity: 0.4, noiseAmount: 0.08, flowBias: .zero, radialBurstBias: 0)
        case .running:
            // 速く激しい変形
            return ActivityStyle(rotationSpeed: 0.5, deformationIntensity: 0.85, noiseAmount: 0.2, flowBias: .zero, radialBurstBias: 0)
        case .automotive:
            // 要素が流れるようなスライド。回転は控えめに。
            return ActivityStyle(rotationSpeed: 0.1, deformationIntensity: 0.3, noiseAmount: 0.05, flowBias: CGVector(dx: 0.6, dy: 0), radialBurstBias: 0)
        case .cycling:
            // 回転運動の強調（歩行より一段強い規則的な回転）
            return ActivityStyle(rotationSpeed: 0.32, deformationIntensity: 0.5, noiseAmount: 0.1, flowBias: .zero, radialBurstBias: 0)
        case .unknown:
            // stationaryに準じる控えめな模様
            return ActivityStyle(rotationSpeed: 0.06, deformationIntensity: 0.15, noiseAmount: 0.03, flowBias: .zero, radialBurstBias: 0)
        }
    }
}
