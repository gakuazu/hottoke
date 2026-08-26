import SwiftUI
import UIKit

/// KaleidoscopeRendererを毎フレーム呼び出して描画するUIView。
/// SwiftUIのCanvas/GraphicsContextではなく、直接CGContextへ描画するUIKitのUIViewを使うことで、
/// 動画書き出し側（KaleidoscopeVideoExporter）と全く同じ描画コードを共有できるようにしている。
final class KaleidoscopeUIView: UIView {
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
        KaleidoscopeRenderer.render(into: ctx, size: rect.size, parameters: parameters)
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
