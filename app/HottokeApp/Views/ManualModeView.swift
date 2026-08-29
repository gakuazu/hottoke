import SwiftUI

/// 手動クリエイティブモード画面。docs/02-spec.md 2章 #3 / docs/03-design.md 画面3、
/// docs/03b-visual-prototype-learnings.md「操作・モーション」節に対応。
struct ManualModeView: View {
    @StateObject private var motion = MotionInputService()
    @State private var symmetryCount: Double = 8
    @State private var speed: Double = 0.5
    @State private var palette: KaleidoscopePalette = .daytime
    @State private var patternStyle: PatternStyle = .waves
    @State private var detail: Double = 0.5
    @State private var seed: UInt64 = 1
    @State private var dragRotation: Double = 0
    @State private var popScale: CGFloat = 1.0
    @State private var startTime: TimeInterval = Date.timeIntervalSinceReferenceDate
    // パネルが模様の下半分を覆ってしまう問題への対処。ヘッダー行をタップすると
    // スライダー・スウォッチ群を折りたたみ、ヘッダーだけの薄い帯にできる
    // （ブラウザプロトタイプの.panel-inner.collapsedと同じ考え方）。
    @State private var isPanelCollapsed = false
    // 振った瞬間の「ポン」という視覚フィードバック用。triggerShuffle()でこの時刻を記録し、
    // TimelineViewの毎フレームでそこからの経過時間に応じてradialBurstを1→0へ減衰させる。
    // （KaleidoscopeCanvasViewはUIViewRepresentableでAnimatableではないため、
    //   withAnimationで@Stateを直接変えても滑らかには補間されない。経過時間から都度計算する）
    @State private var burstStartTime: TimeInterval?

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                // アイドル時もゆっくり回転・脈動させ、静止画に見えないようにする（docs/03b）。
                // 回転速度そのものは一定にせず、プロトタイプのspeedDriftと同じ考え方で
                // ゆっくり加速・減速（たまに一瞬逆回転も）する「呼吸する回転」にする
                // （KaleidoscopeDynamics参照。基準速度speed*0.25は従来の見た目の速さを踏襲）。
                let baseRotation = KaleidoscopeDynamics.organicRotationAngle(elapsed: elapsed, angularSpeed: speed * 0.25)
                let pulse = (sin(elapsed * 1.6) + 1) / 2

                // 振った瞬間の放射状バースト: burstStartTimeからの経過時間で1→0へイーズアウト減衰。
                let burstDuration = 0.6
                let radialBurst: Double = {
                    guard let start = burstStartTime else { return 0 }
                    let t = min(1, max(0, (elapsed - start) / burstDuration))
                    return (1 - t) * (1 - t)
                }()

                KaleidoscopeCanvasView(parameters: KaleidoscopeParameters(
                    symmetryCount: Int(symmetryCount),
                    seed: seed,
                    palette: palette,
                    rotation: baseRotation + motion.tiltRotation + dragRotation,
                    pulsePhase: pulse,
                    deformationIntensity: 0.5,
                    rotationSpeed: speed,
                    shardDensity: 0.65,
                    noiseAmount: 0.08,
                    flowOffset: motion.flowOffset,
                    radialBurst: radialBurst,
                    time: elapsed - startTime,
                    patternStyle: patternStyle,
                    detail: detail
                ))
                .scaleEffect(popScale)
                .ignoresSafeArea()
            }
            .gesture(
                // ドラッグ: 模様全体を回転させる（傾ける操作の代替、docs/03b「操作・モーション」）
                DragGesture()
                    .onChanged { value in dragRotation += value.translation.width * 0.002 }
            )
            .onChange(of: motion.pulseTrigger) { _, _ in
                triggerShuffle()
            }

            controlOverlay
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .statusBarHidden()
    }

    private func triggerShuffle() {
        seed = UInt64.random(in: 1...UInt64.max)
        // 揺らした瞬間の「ポン」という視覚フィードバック（docs/03b: 中心からの衝撃波リング、
        // 模様全体のわずかな拡大→戻り）。放射状バーストとスケールのポップを同じタイミングで発生させる。
        burstStartTime = Date.timeIntervalSinceReferenceDate
        withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
            popScale = 1.06
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                popScale = 1.0
            }
        }
    }

    private var controlOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                panelHeader

                if !isPanelCollapsed {
                    Label("振ってシャッフル / 傾けて回転", systemImage: "hand.draw")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))

                    // 9スタイル分は横一列に並べきれないため、横スクロールにする
                    // （5スタイル追加時に見た目が崩れないよう対応。docs/04-build-log.md参照）。
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PatternStyle.allCases) { style in
                                styleSwatch(style)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("対称数: \(Int(symmetryCount))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $symmetryCount, in: 4...16, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("密度・複雑さ")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $detail, in: 0...1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("速度")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $speed, in: 0...1)
                    }
                    HStack(spacing: 10) {
                        ForEach(KaleidoscopePalette.all) { item in
                            paletteSwatch(item)
                        }
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    /// パネル上部のヘッダー行。現在のスタイル名とシェブロンを表示し、タップで
    /// パネルの折りたたみ/展開を切り替える（模様の下半分が隠れてしまう不具合の対処）。
    private var panelHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                isPanelCollapsed.toggle()
            }
        } label: {
            HStack {
                Text(patternStyle.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .rotationEffect(.degrees(isPanelCollapsed ? -90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func styleSwatch(_ style: PatternStyle) -> some View {
        Button {
            // ロック済みスタイル（将来課金で解放予定）はタップしても選択できない。
            // paletteSwatchの鍵アイコン表示と同じ考え方（今回は土台のみ、実際の解放ロジックは未実装）。
            guard !style.isLocked else { return }
            patternStyle = style
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle().stroke(Color.white.opacity(patternStyle == style ? 0.9 : 0.2), lineWidth: patternStyle == style ? 2 : 1)
                        )
                    if style.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Image(systemName: style.iconName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(patternStyle == style ? 1 : 0.6))
                    }
                }
                Text(style.shortLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(patternStyle == style ? 0.9 : 0.5))
            }
        }
    }

    private func paletteSwatch(_ item: KaleidoscopePalette) -> some View {
        Button {
            guard !item.isLocked else { return }
            palette = item
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().stroke(Color.white.opacity(palette.id == item.id ? 0.9 : 0.2), lineWidth: palette.id == item.id ? 2 : 1)
                    )
                if item.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
