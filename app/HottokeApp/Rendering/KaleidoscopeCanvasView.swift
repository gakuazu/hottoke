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
///
/// 追加の非同期化（実機フィードバック対応）:
/// 「waves（波の干渉）スタイルだけ周期的にカクつく」という実機報告への対処。waves は
/// 4スタイルの中でもとりわけ重く（輪スロット最大14本×輪ごと220点サンプリング×
/// 帯塗り+ストローク2回+きらめきループ）、55msごとの再生成1回分がメインスレッドの
/// 描画を同期的にブロックしてしまうと、waves のようなスタイルではその瞬間だけ
/// ワンテンポ詰まりコマ落ちとして体感されてしまう。そこで扇形の再生成自体は
/// `DispatchQueue.global(qos: .userInteractive)`上で行い、完了したらメインスレッドで
/// キャッシュ画像を差し替えて`setNeedsDisplay()`する形に変更した。`draw(_:)`は常に
/// 「その時点でキャッシュにある画像」を使って即座に描画し、再生成の完了を待たない
/// （多少古い画像のままでもコマ落ちさせないことを優先する）。二重に同時実行が
/// 走らないよう`isRegeneratingWedge`フラグで多重起動を防いでいる。
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
    /// 現在バックグラウンドで扇形を再生成中かどうか。多重起動防止用（メインスレッドでのみ読み書き）。
    private var isRegeneratingWedge = false
    /// 再生成中に別のパラメータへ変わった場合に備え、直近に要求されたキーを覚えておく。
    /// 再生成完了時にこれと食い違っていれば、そのままもう一度バックグラウンド再生成を予約する。
    private var pendingRegenerationKey: WedgeCacheKey?

    private static let regenerationQueue = DispatchQueue(label: "com.gakuazu.hottoke.kaleidoscope-wedge", qos: .userInteractive)

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
        if key != cachedWedgeKey {
            // 内容に関わるパラメータが変わった（55ms経過含む）ので再生成が必要だが、
            // メインスレッドをブロックしないようバックグラウンドで行う。draw(_:)自体は
            // 待たずに、その時点でキャッシュにある画像（多少古くても構わない）で即座に描く。
            requestWedgeRegeneration(key: key, parameters: parameters, size: rect.size)
        }

        if let wedgeImage = cachedWedgeImage {
            KaleidoscopeRenderer.stampWedge(wedgeImage, into: ctx, size: rect.size, parameters: parameters)
        } else {
            // まだ一度も扇形が生成できていない場合（初回フレームなど）でも
            // 描画ループ自体は止めない（docs/03b 安全設計）。
            ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
            ctx.fill(rect)
        }

        ctx.restoreGState()
    }

    /// 扇形の再生成をバックグラウンドキューに投げる。すでに再生成中の場合は多重起動せず、
    /// 代わりに「再生成完了後にもう一度このキーで作り直す必要がある」ことだけ覚えておく。
    private func requestWedgeRegeneration(key: WedgeCacheKey, parameters: KaleidoscopeParameters, size: CGSize) {
        guard !isRegeneratingWedge else {
            pendingRegenerationKey = key
            return
        }
        isRegeneratingWedge = true
        pendingRegenerationKey = nil

        Self.regenerationQueue.async { [weak self] in
            let image = KaleidoscopeRenderer.renderWedgeImage(size: size, parameters: parameters)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cachedWedgeKey = key
                self.cachedWedgeImage = image
                self.isRegeneratingWedge = false
                self.setNeedsDisplay()

                // 再生成中に別のパラメータへ進んでいた場合、そのキーで改めて再生成を予約する。
                if let pendingKey = self.pendingRegenerationKey, pendingKey != key {
                    self.requestWedgeRegeneration(key: pendingKey, parameters: self.parameters, size: size)
                }
            }
        }
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
