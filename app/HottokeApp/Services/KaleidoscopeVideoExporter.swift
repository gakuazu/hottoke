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

    /// - Parameter styleOverride: 明示的に使うスタイルを指定する場合に渡す（「今日の模様」画面で
    ///   ユーザーが試しにスタイルを選び直した場合）。`nil`なら従来通り`data.dominantMovingKind`
    ///   から自動選択する。
    func exportDailyPattern(data: DailyActivityData, to outputURL: URL, styleOverride: PatternStyle? = nil) async throws {
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
        let videoSizeValue = videoSize
        // その日いちばん長く続いた「移動系」の活動種別から、動画全体で使う模様スタイルを1つに
        // 決める（docs/02-spec.md参照）。時間帯やセグメントが変わるたびにスタイル自体が
        // 切り替わると忙しない見た目になるため、スタイルは動画を通して固定し、密度・複雑さ
        // (detail)の方をセグメントごとの活動の強さで変化させる（buildParametersTimeline内）。
        // styleOverrideが指定されていればそちらを優先する（ユーザーが試しにスタイルを選んだ場合）。
        let patternStyle = styleOverride ?? data.dominantMovingKind.map(PatternStyle.style(for:)) ?? .waves

        // フレームごとのレンダリングパラメータは、書き込みループの中で毎回その場計算するのではなく
        // ここで一括して事前計算する（Self.buildParametersTimeline参照）。理由は、活動区間の境界を
        // またぐ際にrotationSpeed等が滑らかに繋がるよう時間窓で平滑化し、さらに回転角を
        // フレームごとの角速度から数値積算する必要があり、「1フレームだけを見て計算する」純関数
        // では成立しないため（実機フィードバックで判明した、動画終盤の模様が震える不具合の対策）。
        let parametersTimeline = Self.buildParametersTimeline(
            keyframes: keyframes,
            data: data,
            seed: seed,
            duration: duration,
            fps: fps,
            patternStyle: patternStyle
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var frameIndex = 0
            let queue = DispatchQueue(label: "com.gakuazu.hottoke.kaleidoscope-export")
            let fpsValue = fps

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

                    let parameters = parametersTimeline[min(frameIndex, parametersTimeline.count - 1)]

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

    /// キーフレーム列 → 動画全フレーム分のレンダリングパラメータへの一括変換。
    /// docs/02-spec.md 3.2節（動きのマッピング）・3.3節（色パレット）を適用する。
    ///
    /// 実機フィードバック対応（動画終盤が震えるようにガタガタする不具合）:
    /// `KaleidoscopeTimelineBuilder.buildKeyframes`が返す`activityKind`は活動区間の境界で
    /// ハードに切り替わる値のため、そこから求まる`rotationSpeed`/`deformationIntensity`/
    /// `noiseAmount`/`flowBias`をフレームごとにそのまま使うと、区間境界のたびにパラメータが
    /// 瞬時にジャンプしてしまう。特に`rotation`は「角速度が動画全体で一定」という前提の
    /// 閉じた式（`organicRotationAngle`）で求めていたため、`angularSpeed`が変わった瞬間に
    /// 過去の角度全体がスケールし直され、隣接フレーム間で回転角が不連続にジャンプしていた。
    /// そこでここでは、
    ///   1. 活動由来の生パラメータをまず全フレーム分並べ、時間窓（約1秒）の移動平均で平滑化する
    ///   2. 回転角は平滑化後の`rotationSpeed`を使い、`organicRotationAngle`のような閉じた式では
    ///      なく、`KaleidoscopeDynamics.speedDriftMultiplier`を使ってフレームごとに数値積算する
    /// という2段階の処理で、区間境界をまたいでも滑らかに繋がるようにしている。
    // internal（privateではない）にしているのは、ユニットテスト（@testable import）から
    // 直接呼び出して「フレーム間でパラメータが滑らかに変化するか」を検証できるようにするため。
    static func buildParametersTimeline(
        keyframes: [KaleidoscopeKeyframe],
        data: DailyActivityData,
        seed: UInt64,
        duration: Double,
        fps: Int32,
        patternStyle: PatternStyle
    ) -> [KaleidoscopeParameters] {
        let frameCount = keyframes.count
        guard frameCount > 0 else { return [] }

        // 1. 活動区間由来の生パラメータをフレームごとに並べる（この時点では区間境界で
        //    瞬時に切り替わる、平滑化前の値）。
        let rawStyles = keyframes.map { ActivityStyle.style(for: $0.activityKind) }

        // 2. 前後 約0.5秒（合計約1秒、24fpsなら約24フレーム）の移動平均で平滑化する。
        //    区間境界をまたいでも急激なジャンプが起きないようにするのが目的。
        let smoothedRotationSpeed = movingAverage(rawStyles.map { $0.rotationSpeed }, windowSeconds: 1.0, fps: fps)
        let smoothedDeformation = movingAverage(rawStyles.map { $0.deformationIntensity }, windowSeconds: 1.0, fps: fps)
        let smoothedNoise = movingAverage(rawStyles.map { $0.noiseAmount }, windowSeconds: 1.0, fps: fps)
        let smoothedFlowX = movingAverage(rawStyles.map { $0.flowBias.dx }, windowSeconds: 1.0, fps: fps)
        let smoothedFlowY = movingAverage(rawStyles.map { $0.flowBias.dy }, windowSeconds: 1.0, fps: fps)

        // 3. 各フレームの経過時間(秒)。
        let elapsedTimes: [Double] = (0..<frameCount).map { index in
            frameCount > 1 ? duration * Double(index) / Double(frameCount - 1) : 0
        }

        // 4. 回転角は「角速度が一定」前提の閉じた式を使わず、平滑化済みのrotationSpeedを
        //    フレームごとの角速度として、1フレーム分の経過時間(dt)ずつ数値積算する。
        //    speedDriftMultiplierは organicRotationAngle が前提にしている「呼吸するような
        //    加速・減速」の瞬間倍率（長期平均1）で、時間変化するrotationSpeedにも自然に追従する。
        var rotations = [Double](repeating: 0, count: frameCount)
        if frameCount > 1 {
            for index in 1..<frameCount {
                let dt = elapsedTimes[index] - elapsedTimes[index - 1]
                let multiplier = KaleidoscopeDynamics.speedDriftMultiplier(elapsed: elapsedTimes[index])
                rotations[index] = rotations[index - 1] + smoothedRotationSpeed[index] * multiplier * dt
            }
        }

        // docs/02-spec.md 3.2節「floorsAscended → 中心から外側・上方向への広がり」の簡易版。
        // 正確な発生タイミングまでは扱わず、その日の合計階数を一定の強さのオーバーレイとして重ねる。
        let radialBurst = min(1.0, Double(data.floorsAscended) / 20.0) * 0.5

        // 対称数(symmetryCount)も以前は8固定だったため、模様の根本的な構造が日によって
        // 一切変わらなかった（実機フィードバック対応）。その日の歩数とseedを組み合わせて
        // 6〜12の範囲で決め、動画を通して1つに固定する（対称数が動画の途中で変わると
        // 継ぎ目が目立つため）。
        let symmetryCount = 6 + Int((seed &+ UInt64(max(0, data.stepCount))) % 7)

        // 歩数が多い日ほど模様が細かく込み入って見えるようにする（オーナーからの要望）。
        // 1万5千歩でほぼ頭打ちになるよう正規化し、密度(detail)に上乗せする。
        // セグメントごとの活動の強さ（smoothedDeformation）による変化は維持しつつ、
        // その日全体の歩数が多いほど底上げされる形にする。
        let stepFactor = min(1.0, Double(max(0, data.stepCount)) / 15000.0)

        return (0..<frameCount).map { index in
            let keyframe = keyframes[index]
            let elapsed = elapsedTimes[index]
            let pulsePhase = (sin(elapsed * 2.0) + 1) / 2

            return KaleidoscopeParameters(
                symmetryCount: symmetryCount,
                seed: seed &+ keyframe.timeOfDay.stableIndex,
                palette: KaleidoscopePalette.forTimeOfDay(keyframe.timeOfDay),
                rotation: rotations[index],
                pulsePhase: pulsePhase,
                deformationIntensity: smoothedDeformation[index],
                rotationSpeed: smoothedRotationSpeed[index],
                shardDensity: 0.6,
                noiseAmount: smoothedNoise[index],
                flowOffset: CGVector(dx: smoothedFlowX[index] * 20, dy: smoothedFlowY[index] * 20),
                radialBurst: radialBurst,
                time: elapsed,
                // スタイル自体は動画全体で1つに固定（呼び出し元でdominantMovingKindから決定済み）。
                // 密度・複雑さ(detail)はセグメントごとの活動の強さ(deformationIntensity)を基本に、
                // その日全体の歩数(stepFactor)ぶん底上げする。動画の中でも活動が盛り上がる場面
                // ほど模様が込み入り、かつ歩数が多い日全体としても他の日より込み入って見える。
                // detailDrift/breathEnvelopeによる揺らぎはKaleidoscopeRenderer側でtimeから適用される。
                patternStyle: patternStyle,
                detail: min(1.0, smoothedDeformation[index] + stepFactor * 0.35)
            )
        }
    }

    /// 前後 `windowSeconds/2` 秒ぶん（端では取れる範囲だけ）を単純平均する移動平均。
    /// 活動区間の境界で値が瞬時に切り替わるのを防ぎ、フレーム間で滑らかに繋げるために使う。
    private static func movingAverage(_ values: [Double], windowSeconds: Double, fps: Int32) -> [Double] {
        guard values.count > 1 else { return values }
        let halfWindow = max(1, Int((windowSeconds * Double(fps) / 2).rounded()))
        var result = [Double](repeating: 0, count: values.count)
        var runningSum = 0.0
        var windowCount = 0
        // 単純な累積和（尺取り法）で O(n) に計算する。
        var lo = 0
        var hi = -1
        for index in 0..<values.count {
            let targetLo = max(0, index - halfWindow)
            let targetHi = min(values.count - 1, index + halfWindow)
            while hi < targetHi {
                hi += 1
                runningSum += values[hi]
                windowCount += 1
            }
            while lo < targetLo {
                runningSum -= values[lo]
                windowCount -= 1
                lo += 1
            }
            result[index] = runningSum / Double(windowCount)
        }
        return result
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
