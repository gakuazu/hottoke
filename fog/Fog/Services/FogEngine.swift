import UIKit
import Combine

/// 画面全体で共有する部品（設定・息検知・傾き・背景画像）
final class FogEngine: ObservableObject {
    let settings = FogSettings()
    let breath = BreathMonitor()
    let motion = MotionService()
    @Published var showSettings = false
    let fogRequests = PassthroughSubject<Void, Never>()
    /// (くっきりした背景, ぼかした背景)
    @Published private(set) var images: (sharp: CGImage, blurred: CGImage)?

    init() {
        setBackground(SceneImage.makeDefault())
    }

    func setBackground(_ image: UIImage) {
        let small = SceneImage.downscaled(image)
        guard let sharp = small.cgImage, let blur = SceneImage.blurred(small) else { return }
        images = (sharp, blur)
    }

    func requestFullFog() { fogRequests.send() }

    func start() {
        breath.start()
        motion.start()
    }

    func stop() {
        breath.stop()
        motion.stop()
    }
}
