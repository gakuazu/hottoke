import AVFoundation
import CoreGraphics
import Foundation

/// docs/02-spec.md 3章の処理フローに沿って、1日分の活動データから模様動画(mp4)を
/// その場でオフライン生成する。AVAssetWriter + KaleidoscopeRenderer(CoreGraphics)の組み合わせ。
final class KaleidoscopeVideoExporter {

    struct ExportError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MVPスコープ: 端末上でその場生成することを優先し、解像度・フレームレートは控えめにする。
    private let videoSize = CGSize(width: 720, height: 720)
    private let fps: Int32 = 24
    private let duration: Double = 28 // 秒（spec 3.1節「目安30秒前後」）

    func exportDailyPattern(data: DailyActivityData, to outputURL: URL) async throws {
        let frameCount = max(1, Int(duration * Double(fps)))
        let keyframes = KaleidoscopeTimelineBuilder.buildKeyframes(from: data, frameCount: frameCount)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(videoSize.width),
            kCVPixelBufferHeightKey as String: Int(videoSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: pixelBufferAttributes)

        guard writer.canAdd(input) else {
            throw ExportError(message: "動画エンコーダーの初期化に失敗しました。")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw ExportError(message: writer.error?.localizedDescription ?? "動画の書き出し開始に失敗しました。")
        }
        writer.startSession(atSourceTime: .zero)

        let seed = UInt64(Date().timeIntervalSince1970)
        let fpsValue = fps
        let videoSizeValue = videoSize
        let durationValue = duration
        // その日いちばん長く続いた「移動系」の活動種別から、動画全体で使う模様スタイルを1つに
        // 決める（docs/02-spec.md参照）。時間帯やセグメントが変わるたびにスタイル自体が
        // 切り替わると忙しない見た目になるため、スタイルは動画を通して固定し、密度・複雑さ
        // (detail)の方をセグメントごとの活動の強さで変化させる（parameters(for:)内）。
        let patternStyle = data.dominantMovingKind.map(PatternStyle.style(for:)) ?? .waves

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var frameIndex = 0
            let queue = DispatchQueue(label: "com.gakuazu.hottoke.kaleidoscope-export")

            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if frameIndex >= frameCount {
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume(returning: ())
                            } else {
                                continuation.resume(throwing: writer.error ?? ExportError(message: "動画の書き出しに失敗しました。"))
                            }
                        }
                        return
                    }

                    let keyframe = keyframes[min(frameIndex, keyframes.count - 1)]
                    let progress = frameCount > 1 ? Double(frameIndex) / Double(frameCount - 1) : 0
                    let parameters = Self.parameters(for: keyframe, progress: progress, data: data, seed: seed, duration: durationValue, patternStyle: patternStyle)

                    guard let pixelBufferPool = adaptor.pixelBufferPool else {
                        continuation.resume(throwing: ExportError(message: "フレームバッファの確保に失敗しました。"))
                        return
                    }
                    var pixelBufferOut: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBufferOut)
                    guard let pixelBuffer = pixelBufferOut else {
                        continuation.resume(throwing: ExportError(message: "フレームバッファの確保に失敗しました。"))
                        return
                    }

                    Self.render(parameters: parameters, size: videoSizeValue, into: pixelBuffer)

                    let time = CMTime(value: CMTimeValue(frameIndex), timescale: fpsValue)
                    if !adaptor.append(pixelBuffer, withPresentationTime: time) {
                        continuation.resume(throwing: writer.error ?? ExportError(message: "フレームの書き込みに失敗しました。"))
                        return
                    }
                    frameIndex += 1
                }
            }
        }
    }

    /// キーフレーム情報 → 実際のレンダリングパラメータへの変換。
    /// docs/02-spec.md 3.2節（動きのマッピング）・3.3節（色パレット）を適用する。
    private static func parameters(for keyframe: KaleidoscopeKeyframe, progress: Double, data: DailyActivityData, seed: UInt64, duration: Double, patternStyle: PatternStyle) -> KaleidoscopeParameters {
        let style = ActivityStyle.style(for: keyframe.activityKind)
        let elapsed = progress * duration
        // 回転速度も一定にせず、プロトタイプのspeedDriftと同じ「呼吸する回転」にする
        // （KaleidoscopeDynamics参照）。動画は時系列に沿った1本のタイムラインなので、
        // ライブプレビューと同様に経過時間(elapsed)だけから閉じた式で回転角を求める。
        let rotation = KaleidoscopeDynamics.organicRotationAngle(elapsed: elapsed, angularSpeed: style.rotationSpeed)
        let pulsePhase = (sin(elapsed * 2.0) + 1) / 2

        // docs/02-spec.md 3.2節「floorsAscended → 中心から外側・上方向への広がり」の簡易版。
        // 正確な発生タイミングまでは扱わず、その日の合計階数を一定の強さのオーバーレイとして重ねる。
        let radialBurst = min(1.0, Double(data.floorsAscended) / 20.0) * 0.5

        return KaleidoscopeParameters(
            symmetryCount: 8,
            seed: seed &+ keyframe.timeOfDay.stableIndex,
            palette: KaleidoscopePalette.forTimeOfDay(keyframe.timeOfDay),
            rotation: rotation,
            pulsePhase: pulsePhase,
            deformationIntensity: style.deformationIntensity,
            rotationSpeed: style.rotationSpeed,
            shardDensity: 0.6,
            noiseAmount: style.noiseAmount,
            flowOffset: CGVector(dx: style.flowBias.dx * 20, dy: style.flowBias.dy * 20),
            radialBurst: radialBurst,
            time: elapsed,
            // スタイル自体は動画全体で1つに固定（呼び出し元でdominantMovingKindから決定済み）。
            // 密度・複雑さ(detail)はセグメントごとの活動の強さ(deformationIntensity)を流用し、
            // 動画の中でも活動が盛り上がる場面ほど模様が込み入るようにする。
            // detailDrift/breathEnvelopeによる揺らぎはKaleidoscopeRenderer側でtimeから適用される。
            patternStyle: patternStyle,
            detail: style.deformationIntensity
        )
    }

    private static func render(parameters: KaleidoscopeParameters, size: CGSize, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // 失敗しても真っ黒/未定義のフレームを書き込まないよう、まず落ち着いた色で塗りつぶしておく
        // （docs/03b 安全設計: 描画ループ自体は止めない）。
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        KaleidoscopeRenderer.render(into: context, size: CGSize(width: width, height: height), parameters: parameters)
    }
}
