import Foundation
import CoreGraphics

enum FogMath {
    /// じわっと再び曇る（1 = 完全に曇り）
    static func refogged(_ v: Float, rate: Float, dt: Float) -> Float {
        min(1, v + rate * dt)
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// CoreMotion の重力(x:右, y:上)から画面上の重力方向(x:右, y:下)と強さ(0...1)を求める
    static func screenGravity(x: Double, y: Double) -> (dx: Float, dy: Float, strength: Float) {
        let mag = (x * x + y * y).squareRoot()
        if mag < 0.0001 { return (0, 1, 0) }
        return (Float(x / mag), Float(-y / mag), Float(min(1, mag)))
    }
}

struct FogDrop {
    var x: Float
    var y: Float
    var radius: Float
    var targetRadius: Float
    var vx: Float = 0
    var vy: Float = 0
    var wait: Float
    var moving = false
    var pauseTimer: Float
}

/// 曇りの状態（格子）と水滴。UIに依存しない純粋なロジック。座標の単位は「セル」。
final class FogField {
    let cols: Int
    let rows: Int
    private(set) var fog: [Float]
    private(set) var drops: [FogDrop] = []
    var dirty = true
    static let maxDrops = 40
    private var travel: Float = 0

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        fog = [Float](repeating: 1, count: cols * rows)
    }

    /// 線分(from→to)の周りを拭う。minFog > 0 だと完全には拭わない（水滴の筋用）
    func wipe(fromX: Float, fromY: Float, toX: Float, toY: Float, radius: Float, minFog: Float = 0) {
        let x0 = max(0, Int((min(fromX, toX) - radius).rounded(.down)))
        let x1 = min(cols - 1, Int((max(fromX, toX) + radius).rounded(.up)))
        let y0 = max(0, Int((min(fromY, toY) - radius).rounded(.down)))
        let y1 = min(rows - 1, Int((max(fromY, toY) + radius).rounded(.up)))
        if x0 > x1 || y0 > y1 { return }
        let sx = toX - fromX, sy = toY - fromY
        let len2 = sx * sx + sy * sy
        for cy in y0...y1 {
            for cx in x0...x1 {
                let px = Float(cx) + 0.5, py = Float(cy) + 0.5
                var t: Float = 0
                if len2 > 0.0001 { t = min(1, max(0, ((px - fromX) * sx + (py - fromY) * sy) / len2)) }
                let dx = px - (fromX + sx * t), dy = py - (fromY + sy * t)
                let d = (dx * dx + dy * dy).squareRoot()
                if d >= radius { continue }
                let s = FogMath.smoothstep(0.45, 1, d / radius)
                let target = minFog + (1 - minFog) * s
                let i = cy * cols + cx
                if target < fog[i] { fog[i] = target }
            }
        }
        dirty = true
    }

    func addFog(_ amount: Float) {
        if amount <= 0 { return }
        for i in 0..<fog.count { fog[i] = min(1, fog[i] + amount) }
        dirty = true
    }

    func refog(dt: Float, rate: Float) {
        var any = false
        for i in 0..<fog.count where fog[i] < 1 {
            fog[i] = FogMath.refogged(fog[i], rate: rate, dt: dt)
            any = true
        }
        if any { dirty = true }
    }

    /// 拭いた距離に応じて、縁にときどき水滴を作る。frequency は 0...1
    func maybeSpawnDrop(atX x: Float, y: Float, distance: Float, wipeRadius: Float,
                        frequency: Float, random: () -> Float) {
        travel += distance
        let interval: Float = 6
        while travel >= interval {
            travel -= interval
            if drops.count >= Self.maxDrops { continue }
            if random() < frequency * 0.12 {
                let angle = random() * 2 * .pi
                let r = 1.4 + random() * 1.8
                let px = x + cos(angle) * wipeRadius * 0.95
                let py = y + sin(angle) * wipeRadius * 0.95
                guard px >= 0, px < Float(cols), py >= 0, py < Float(rows) else { continue }
                drops.append(FogDrop(x: px, y: py, radius: r * 0.5, targetRadius: r,
                                     wait: 0.5 + random() * 2.5, pauseTimer: 0.6 + random() * 1.8))
                wipe(fromX: px, fromY: py, toX: px, toY: py, radius: r * 1.2, minFog: 0.4)
            }
        }
    }

    /// 重力方向へ水滴を動かす。通った跡は少し拭われる
    func stepDrops(dt: Float, gx: Float, gy: Float, strength: Float, random: () -> Float) {
        var i = 0
        while i < drops.count {
            var d = drops[i]
            if !d.moving {
                d.wait -= dt
                d.radius += (d.targetRadius - d.radius) * min(1, dt * 3)
                if d.wait <= 0 { d.moving = true }
            } else {
                let accel: Float = 140 * strength * (0.6 + d.radius * 0.25)
                d.vx += gx * accel * dt
                d.vy += gy * accel * dt
                let damp = exp(-2.2 * dt)
                d.vx *= damp
                d.vy *= damp
                let nx = d.x + d.vx * dt, ny = d.y + d.vy * dt
                if strength > 0.05 {
                    wipe(fromX: d.x, fromY: d.y, toX: nx, toY: ny, radius: max(1, d.radius * 0.85), minFog: 0.3)
                }
                d.x = nx
                d.y = ny
                d.radius -= dt * 0.12
                d.pauseTimer -= dt
                if d.pauseTimer <= 0 {
                    d.moving = false
                    d.vx = 0
                    d.vy = 0
                    d.wait = 0.3 + random() * 1.2
                    d.pauseTimer = 0.6 + random() * 1.8
                }
            }
            let margin: Float = 4
            let off = d.x < -margin || d.x > Float(cols) + margin || d.y < -margin || d.y > Float(rows) + margin
            if off || d.radius < 0.7 {
                drops.remove(at: i)
            } else {
                drops[i] = d
                i += 1
            }
        }
        if !drops.isEmpty { dirty = true }
    }
}
