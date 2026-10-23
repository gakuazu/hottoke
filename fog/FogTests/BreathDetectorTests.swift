import XCTest
@testable import Fog

final class BreathDetectorTests: XCTestCase {
    private func run(_ d: inout BreathDetector, rms: Double, low: Double, seconds: Double) {
        var t = 0.0
        while t < seconds { d.feed(rms: rms, lowRatio: low, dt: 0.02); t += 0.02 }
    }

    func testQuietRoomIsNotBreath() {
        var d = BreathDetector()
        run(&d, rms: 0.004, low: 0.5, seconds: 2)
        XCTAssertFalse(d.isBreathing)
        XCTAssertEqual(d.intensity, 0, accuracy: 0.001)
    }

    func testSustainedLowRumbleIsBreath() {
        var d = BreathDetector()
        run(&d, rms: 0.004, low: 0.5, seconds: 1)
        run(&d, rms: 0.15, low: 0.7, seconds: 0.5)
        XCTAssertTrue(d.isBreathing)
        XCTAssertGreaterThan(d.intensity, 0.3)
    }

    func testShortBlipIsIgnored() {
        var d = BreathDetector()
        run(&d, rms: 0.004, low: 0.5, seconds: 1)
        run(&d, rms: 0.3, low: 0.7, seconds: 0.06)
        XCTAssertFalse(d.isBreathing)
    }

    func testHighPitchedSoundIsIgnored() {
        var d = BreathDetector()
        run(&d, rms: 0.004, low: 0.5, seconds: 1)
        run(&d, rms: 0.3, low: 0.05, seconds: 1)
        XCTAssertFalse(d.isBreathing)
    }

    func testSteadyNoiseIsAbsorbedIntoFloor() {
        var d = BreathDetector()
        run(&d, rms: 0.01, low: 0.5, seconds: 1)
        run(&d, rms: 0.03, low: 0.5, seconds: 30)
        XCTAssertEqual(d.noiseFloor, 0.03, accuracy: 0.005)
        XCTAssertFalse(d.isBreathing)
    }

    func testHigherSensitivityLowersMargin() {
        XCTAssertLessThan(BreathDetector.margin(forSensitivity: 0.9), BreathDetector.margin(forSensitivity: 0.2))
    }

    func testIntensityDecaysAfterBreath() {
        var d = BreathDetector()
        run(&d, rms: 0.004, low: 0.5, seconds: 1)
        run(&d, rms: 0.2, low: 0.7, seconds: 0.5)
        run(&d, rms: 0.004, low: 0.5, seconds: 2)
        XCTAssertEqual(d.intensity, 0, accuracy: 0.01)
    }
}
