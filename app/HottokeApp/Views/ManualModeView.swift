import SwiftUI

/// 手動クリエイティブモード画面。docs/02-spec.md 2章 #3 / docs/03-design.md 画面3、
/// docs/03b-visual-prototype-learnings.md「操作・モーション」節に対応。
struct ManualModeView: View {
    @StateObject private var motion = MotionInputService()
    @State private var symmetryCount: Double = 8
    @State private var speed: Double = 0.5
    @State private var palette: KaleidoscopePalette = .daytime
    @State private var seed: UInt64 = 1
    @State private var dragRotation: Double = 0
    @State private var popScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                // アイドル時もゆっくり回転・脈動させ、静止画に見えないようにする（docs/03b）。
                let baseRotation = elapsed * speed * 0.25
                let pulse = (sin(elapsed * 1.6) + 1) / 2

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
                    radialBurst: 0
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
        // 揺らした瞬間の「ポン」という視覚フィードバック（docs/03b）
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
                Label("振ってシャッフル / 傾けて回転", systemImage: "hand.draw")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 4) {
                    Text("対称数: \(Int(symmetryCount))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Slider(value: $symmetryCount, in: 4...16, step: 1)
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
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
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
