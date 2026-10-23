import XCTest
@testable import Fog

final class FogFieldTests: XCTestCase {
    func testRefogLinearAndClamped() {
        XCTAssertEqual(FogMath.refogged(0, rate: 0.1, dt: 1), 0.1, accuracy: 1e-6)
        XCTAssertEqual(FogMath.refogged(0.95, rate: 0.1, dt: 1), 1, accuracy: 1e-6)
    }

    func testWipeClearsCenterKeepsFarCells() {
        let f = FogField(cols: 40, rows: 40)
        f.wipe(fromX: 20, fromY: 20, toX: 20, toY: 20, radius: 6)
        XCTAssertEqual(f.fog[20 * 40 + 20], 0, accuracy: 0.001)
        XCTAssertEqual(f.fog[2 * 40 + 2], 1, accuracy: 0.001)
    }

    func testWipeWithMinFogLeavesPartialFog() {
        let f = FogField(cols: 40, rows: 40)
        f.wipe(fromX: 20, fromY: 20, toX: 20, toY: 20, radius: 6, minFog: 0.3)
        XCTAssertEqual(f.fog[20 * 40 + 20], 0.3, accuracy: 0.001)
    }

    func testRefogEventuallyFullyFogs() {
        let f = FogField(cols: 20, rows: 20)
        f.wipe(fromX: 10, fromY: 10, toX: 10, toY: 10, radius: 5)
        for _ in 0..<200 { f.refog(dt: 0.1, rate: 0.1) }
        XCTAssertEqual(f.fog.min()!, 1, accuracy: 1e-6)
    }

    func testAddFogClamps() {
        let f = FogField(cols: 10, rows: 10)
        f.wipe(fromX: 5, fromY: 5, toX: 5, toY: 5, radius: 4)
        f.addFog(5)
        XCTAssertEqual(f.fog.min()!, 1, accuracy: 1e-6)
    }

    func testScreenGravityUpright() {
        // 縦持ち：重力は (0, -1) → 画面では真下
        let g = FogMath.screenGravity(x: 0, y: -1)
        XCTAssertEqual(g.dx, 0, accuracy: 1e-5)
        XCTAssertEqual(g.dy, 1, accuracy: 1e-5)
        XCTAssertEqual(g.strength, 1, accuracy: 1e-5)
    }

    func testScreenGravityFlatHasNoStrength() {
        let g = FogMath.screenGravity(x: 0.01, y: -0.02)
        XCTAssertLessThan(g.strength, 0.05)
    }

    func testDropSpawnsAlwaysWithFullFrequencyAndRandomZero() {
        let f = FogField(cols: 100, rows: 100)
        f.maybeSpawnDrop(atX: 50, y: 50, distance: 30, wipeRadius: 10, frequency: 1) { 0.0 }
        XCTAssertFalse(f.drops.isEmpty)
    }

    func testNoDropWhenFrequencyZero() {
        let f = FogField(cols: 100, rows: 100)
        f.maybeSpawnDrop(atX: 50, y: 50, distance: 300, wipeRadius: 10, frequency: 0) { 0.5 }
        XCTAssertTrue(f.drops.isEmpty)
    }

    func testDropFallsDownwardAndLeavesTrail() {
        let f = FogField(cols: 100, rows: 200)
        f.maybeSpawnDrop(atX: 50, y: 50, distance: 6, wipeRadius: 10, frequency: 1) { 0.0 }
        guard let start = f.drops.first else { return XCTFail("no drop") }
        for _ in 0..<120 { f.stepDrops(dt: 1.0 / 60, gx: 0, gy: 1, strength: 1) { 0.0 } }
        if let d = f.drops.first { XCTAssertGreaterThan(d.y, start.y) }
        // 水滴の通り道の下方が少し拭われている
        let idx = Int(start.y + 8) * 100 + Int(start.x)
        XCTAssertLessThan(f.fog[idx], 1)
    }

    func testDropStaysWithoutGravity() {
        let f = FogField(cols: 100, rows: 200)
        f.maybeSpawnDrop(atX: 50, y: 50, distance: 6, wipeRadius: 10, frequency: 1) { 0.0 }
        let start = f.drops[0]
        for _ in 0..<120 { f.stepDrops(dt: 1.0 / 60, gx: 0, gy: 1, strength: 0) { 0.0 } }
        XCTAssertEqual(f.drops.first?.y ?? start.y, start.y, accuracy: 0.01)
    }
}
