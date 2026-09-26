import XCTest
@testable import HottokeApp

/// 「GPS自動日記」（`LocationDiaryAnalyzer`/`LocationVisitStore`）のテスト。
/// CoreLocation/CLGeocoderを使わない部分（純粋なロジック・保存）だけを対象にする。
final class LocationDiaryTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    private func sample(_ d: Int, _ h: Int, _ m: Int = 0, lat: Double, lon: Double) -> LocationVisitSample {
        LocationVisitSample(timestamp: date(d, h, m), latitude: lat, longitude: lon)
    }

    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hottoke-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - gridKey

    func testGridKeyGroupsNearbyPointsAndSeparatesFarPoints() {
        // 渋谷付近の2点（数十m差）は同じ格子になる。
        let a = LocationDiaryAnalyzer.gridKey(latitude: 35.6595, longitude: 139.7005)
        let b = LocationDiaryAnalyzer.gridKey(latitude: 35.6596, longitude: 139.7006)
        XCTAssertEqual(a, b)

        // 新宿（数km離れた場所）は別の格子になる。
        let c = LocationDiaryAnalyzer.gridKey(latitude: 35.6905, longitude: 139.7005)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - homeGridKey

    func testHomeGridKeyPicksMostFrequentPlace() {
        let home = (lat: 35.65, lon: 139.70)
        let office = (lat: 35.68, lon: 139.76)
        let samples = [
            sample(10, 8, lat: home.lat, lon: home.lon),
            sample(10, 20, lat: home.lat, lon: home.lon),
            sample(11, 8, lat: home.lat, lon: home.lon),
            sample(11, 12, lat: office.lat, lon: office.lon),
            sample(12, 8, lat: home.lat, lon: home.lon),
        ]
        let homeKey = LocationDiaryAnalyzer.homeGridKey(samples: samples)
        XCTAssertEqual(homeKey, LocationDiaryAnalyzer.gridKey(latitude: home.lat, longitude: home.lon))
    }

    func testHomeGridKeyIsNilWhenNoSamples() {
        XCTAssertNil(LocationDiaryAnalyzer.homeGridKey(samples: []))
    }

    // MARK: - longestStay

    func testLongestStayPicksThePlaceWithMostTotalDuration() {
        // 18日: 0-9時は自宅、9-18時はオフィス、18-24時はまた自宅 → 自宅の合計(15h)がオフィス(9h)より長い。
        let home = (lat: 35.65, lon: 139.70)
        let office = (lat: 35.68, lon: 139.76)
        let daySamples = [
            sample(18, 0, lat: home.lat, lon: home.lon),
            sample(18, 9, lat: office.lat, lon: office.lon),
            sample(18, 18, lat: home.lat, lon: home.lon),
        ]
        let result = LocationDiaryAnalyzer.longestStay(daySamples: daySamples, dayStart: date(18, 0), dayEnd: date(19, 0))
        XCTAssertEqual(result?.gridKey, LocationDiaryAnalyzer.gridKey(latitude: home.lat, longitude: home.lon))
        XCTAssertEqual(result?.latitude ?? 0, home.lat, accuracy: 1e-6)
        XCTAssertEqual(result?.longitude ?? 0, home.lon, accuracy: 1e-6)
    }

    func testLongestStayReturnsNilWhenNoSamplesThatDay() {
        XCTAssertNil(LocationDiaryAnalyzer.longestStay(daySamples: [], dayStart: date(18, 0), dayEnd: date(19, 0)))
    }

    func testLongestStayIgnoresSamplesOutsideTheDayRange() {
        // 17日夜のサンプルは対象外。18日のサンプル1件だけが残る。
        let outside = sample(17, 23, lat: 35.0, lon: 139.0)
        let inside = sample(18, 10, lat: 35.65, lon: 139.70)
        let result = LocationDiaryAnalyzer.longestStay(daySamples: [outside, inside], dayStart: date(18, 0), dayEnd: date(19, 0))
        XCTAssertEqual(result?.gridKey, LocationDiaryAnalyzer.gridKey(latitude: 35.65, longitude: 139.70))
    }

    // MARK: - placeName

    func testPlaceNamePrefersSubLocalityThenLocalityThenNameThenAdministrativeArea() {
        XCTAssertEqual(LocationDiaryAnalyzer.placeName(subLocality: "渋谷", locality: "東京都", name: nil, administrativeArea: nil), "渋谷")
        XCTAssertEqual(LocationDiaryAnalyzer.placeName(subLocality: nil, locality: "渋谷区", name: nil, administrativeArea: "東京都"), "渋谷区")
        XCTAssertEqual(LocationDiaryAnalyzer.placeName(subLocality: nil, locality: nil, name: "代々木公園", administrativeArea: "東京都"), "代々木公園")
        XCTAssertEqual(LocationDiaryAnalyzer.placeName(subLocality: nil, locality: nil, name: nil, administrativeArea: "東京都"), "東京都")
        XCTAssertNil(LocationDiaryAnalyzer.placeName(subLocality: nil, locality: nil, name: nil, administrativeArea: nil))
        XCTAssertNil(LocationDiaryAnalyzer.placeName(subLocality: "", locality: "", name: "", administrativeArea: ""), "空文字は使わない")
    }

    // MARK: - defaultText

    func testDefaultTextPhrasing() {
        XCTAssertEqual(LocationDiaryAnalyzer.defaultText(placeName: "渋谷", isHome: false), "渋谷にいた")
        XCTAssertEqual(LocationDiaryAnalyzer.defaultText(placeName: "渋谷", isHome: true), "自宅で過ごした", "自宅なら地名は出さない")
        XCTAssertNil(LocationDiaryAnalyzer.defaultText(placeName: nil, isHome: false), "地名が分からず自宅でもなければ何も表示しない")
        XCTAssertEqual(LocationDiaryAnalyzer.defaultText(placeName: nil, isHome: true), "自宅で過ごした")
    }

    // MARK: - LocationVisitStore

    func testStoreSavesAndFiltersSamplesByDay() {
        let store = LocationVisitStore(directory: tempDirectory())
        store.add(sample(18, 9, lat: 35.65, lon: 139.70))
        store.add(sample(18, 20, lat: 35.68, lon: 139.76))
        store.add(sample(19, 9, lat: 35.65, lon: 139.70))

        XCTAssertEqual(store.samples(on: date(18), calendar: calendar).count, 2)
        XCTAssertEqual(store.samples(on: date(19), calendar: calendar).count, 1)
        XCTAssertEqual(store.samples(on: date(20), calendar: calendar).count, 0)
    }

    func testStorePrunesSamplesOlderThanRetentionDays() {
        let store = LocationVisitStore(directory: tempDirectory())
        let now = date(30, 12)
        store.add(sample(1, 9, lat: 35.65, lon: 139.70), now: now, calendar: calendar) // 大昔（保持期間より前）
        store.add(sample(29, 9, lat: 35.65, lon: 139.70), now: now, calendar: calendar) // 直近
        XCTAssertEqual(store.samples.count, 1, "保持期間より古いサンプルは自動で消える")
        XCTAssertEqual(store.samples.first?.timestamp, date(29, 9))
    }

    func testRemoveAllClearsEverything() {
        let store = LocationVisitStore(directory: tempDirectory())
        store.add(sample(18, 9, lat: 35.65, lon: 139.70))
        XCTAssertFalse(store.samples.isEmpty)
        store.removeAll()
        XCTAssertTrue(store.samples.isEmpty)
    }

    func testStorePersistsAcrossInstancesAtSameDirectory() {
        let dir = tempDirectory()
        let store = LocationVisitStore(directory: dir)
        store.add(sample(18, 9, lat: 35.65, lon: 139.70))

        let reopened = LocationVisitStore(directory: dir)
        XCTAssertEqual(reopened.samples.count, 1)
        XCTAssertEqual(reopened.samples.first?.latitude ?? 0, 35.65, accuracy: 1e-9)
    }

    // MARK: - 設定（既定はオン）

    func testLocationAndPhotoLinkSettingsDefaultToOn() {
        let suite = UserDefaults(suiteName: "hottoke-test-\(UUID().uuidString)")!
        XCTAssertTrue(LocationDiarySettings.defaultEnabled)
        XCTAssertTrue(LocationDiarySettings.isEnabled(defaults: suite))
        suite.set(false, forKey: LocationDiarySettings.storageKey)
        XCTAssertFalse(LocationDiarySettings.isEnabled(defaults: suite))

        XCTAssertTrue(DiaryPhotoLinkSettings.defaultEnabled)
        XCTAssertTrue(DiaryPhotoLinkSettings.isEnabled(defaults: suite))
        suite.set(false, forKey: DiaryPhotoLinkSettings.storageKey)
        XCTAssertFalse(DiaryPhotoLinkSettings.isEnabled(defaults: suite))
    }
}
