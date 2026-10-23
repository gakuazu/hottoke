import Foundation
import Combine

/// 感触調整用のパラメータ（隠し設定画面から変更。端末に保存）
final class FogSettings: ObservableObject {
    static let defaults = (refogRate: 0.08, breathSensitivity: 0.6, breathGain: 1.6,
                           dropFrequency: 0.5, wipeRadius: 30.0, haptics: true)

    @Published var refogRate: Double { didSet { save("refogRate", refogRate) } }
    @Published var breathSensitivity: Double { didSet { save("breathSensitivity", breathSensitivity) } }
    @Published var breathGain: Double { didSet { save("breathGain", breathGain) } }
    @Published var dropFrequency: Double { didSet { save("dropFrequency", dropFrequency) } }
    @Published var wipeRadius: Double { didSet { save("wipeRadius", wipeRadius) } }
    @Published var haptics: Bool { didSet { UserDefaults.standard.set(haptics, forKey: "fog.haptics") } }

    init() {
        let u = UserDefaults.standard
        func get(_ k: String, _ d: Double) -> Double { u.object(forKey: "fog." + k) as? Double ?? d }
        let d = Self.defaults
        refogRate = get("refogRate", d.refogRate)
        breathSensitivity = get("breathSensitivity", d.breathSensitivity)
        breathGain = get("breathGain", d.breathGain)
        dropFrequency = get("dropFrequency", d.dropFrequency)
        wipeRadius = get("wipeRadius", d.wipeRadius)
        haptics = u.object(forKey: "fog.haptics") as? Bool ?? d.haptics
    }

    private func save(_ k: String, _ v: Double) { UserDefaults.standard.set(v, forKey: "fog." + k) }

    func reset() {
        let d = Self.defaults
        refogRate = d.refogRate
        breathSensitivity = d.breathSensitivity
        breathGain = d.breathGain
        dropFrequency = d.dropFrequency
        wipeRadius = d.wipeRadius
        haptics = d.haptics
    }
}
