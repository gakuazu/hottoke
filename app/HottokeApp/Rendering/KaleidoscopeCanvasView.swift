import SwiftUI
import UIKit

/// KaleidoscopeRendererを毎フレーム呼び出して描画するUIView。
/// SwiftUIのCanvas/GraphicsContextではなく、直接CGContextへ描画するUIKitのUIViewを使うことで、
/// 動画書き出し側（KaleidoscopeVideoExporter）と全く同じ描画コードを共有できるようにしている。
///
/// パフォーマンス対策（扇形ビットマップのキャッシュ）:
/// ManualModeViewは`TimelineView(.animation)`で画面のリフレッシュレート（最大120Hz）ごとに
/// `parameters`を更新するため、`draw(_:)`も同じ頻度で呼ばれる。ここで毎回
/// `KaleidoscopeRenderer.render`をフル実行すると、扇形の中身の再計算（タイル格子・
/// スピログラフの数千点サンプリング・波の輪・フラクタル再帰など）が毎フレーム走ってしまい重い。
///
/// 元になったブラウザプロトタイプ（math-kaleidoscope-prototype.html）は、扇形の中身の再生成
/// （renderWedge、重い）を`WEDGE_INTERVAL = 55ms`ごとに間引き、回転・拡大縮小・スタンプ
/// （stampAll、軽い）だけを毎フレーム動かす設計になっていた。ここではそれと同じ考え方で、
/// 直近に生成した扇形ビットマップを「内容に関わるパラメータ」（対称数・パレット・模様スタイル・
/// シード・密度、および55ms刻みに丸めた時刻）と一緒にキャッシュし、これらが前回と変わって
/// いなければ再生成をスキップしてキャッシュ画像を使い回す。回転・変位・脈動・オーバーレイは
/// 常に最新の`parameters`で毎フレーム描き直すため、動きの滑らかさは損なわれない。
///
/// このキャッシュはUIViewのインスタンスに閉じた状態であり、`KaleidoscopeRenderer`自体は
/// 状態を持たない（動画書き出し側KaleidoscopeVideoExporterは毎フレーム明示的に異なる
/// `time`を指定して`KaleidoscopeRenderer.render`を直接呼ぶため、このキャッシュの影響を受けない）。
final class KaleidoscopeUIView: UIView {
    /// 扇形の中身を再生成する最小間隔（プロトタイプのWEDGE_INTERVALと同じ55ms）。
    private static let wedgeRegenerationInterval: Double = 0.055

    /// 扇形ビットマップの「内容」を左右するパラメータだけを取り出したキャッシュキー。
    /// 時刻は55ms刻みに丸めた値を使うことで、この間隔内では同じキーとみなされる。
    private struct WedgeCacheKey: Equatable {
        let symmetryCount: Int
        let palette: KaleidoscopePalette
        let patternStyle: PatternStyle
        let seed: UInt64
        let detail: Double
        let quantizedTime: Double
        let size: CGSize

        init(parameters: KaleidoscopeParameters, size: CGSize) {
            symmetryCount = max(3, parameters.symmetryCount)
            palette = parameters.palette
            patternStyle = parameters.patternStyle
            seed = parameters.seed
            detail = parameters.detail
            quantizedTime = (parameters.time / KaleidoscopeUIView.wedgeRegenerationInterval).rounded(.down)
            self.size = size
        }
    }

    private var cachedWedgeKey: WedgeCacheKey?
    private var cachedWedgeImage: CGImage?

    var parameters: KaleidoscopeParameters = KaleidoscopeParameters() {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentMode = .redraw
        isOpaque = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()

        let key = WedgeCacheKey(parameters: parameters, size: rect.size)
        let wedgeImage: CGImage?
        if key == cachedWedgeKey, let cachedWedgeImage {
            // 55ms未満しか経っておらず、内容に関わるパラメータも変わっていないので、
            // 重い再生成をスキップしてキャッシュ済みの扇形ビットマップを使い回す。
            wedgeImage = cachedWedgeImage
        } else {
            wedgeImage = KaleidoscopeRenderer.renderWedgeImage(size: rect.size, parameters: parameters)
            cachedWedgeKey = key
            cachedWedgeImage = wedgeImage
        }

        if let wedgeImage {
            KaleidoscopeRenderer.stampWedge(wedgeImage, into: ctx, size: rect.size, parameters: parameters)
        } else {
            // 扇形が生成できなかった場合でも描画ループ自体は止めない（docs/03b 安全設計）。
            ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
            ctx.fill(rect)
        }

        ctx.restoreGState()
    }
}

struct KaleidoscopeCanvasView: UIViewRepresentable {
    var parameters: KaleidoscopeParameters

    func makeUIView(context: Context) -> KaleidoscopeUIView {
        let view = KaleidoscopeUIView()
        view.parameters = parameters
        return view
    }

    func updateUIView(_ uiView: KaleidoscopeUIView, context: Context) {
        uiView.parameters = parameters
    }
}
