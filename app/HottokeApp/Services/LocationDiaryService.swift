import CoreLocation
import Foundation

/// 「GPS自動日記」: 大きく場所が変わったときだけ検知する省電力な方式
/// （`startMonitoringSignificantLocationChanges`）でその日の居場所を推定し、
/// ひとこと日記の文章欄が空のときだけ、デフォルトの下書きを提案する。
///
/// プライバシーへの配慮:
///  ・常時の高精度GPS追跡は使わない（significant location changeのみ）。
///  ・位置情報は端末内（`LocationVisitStore`）にだけ保存し、外部へは一切送信しない。
///  ・設定でオフにすると、監視を止めるだけでなく、貯めていた位置情報も削除する。
///  ・自宅と推定される場所は、地名を出さず「自宅で過ごした」という控えめな表現にする。
@MainActor
final class LocationDiaryService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationDiaryService()

    /// すでに自動生成に成功した日（結果に関わらずではなく、「実際に文章を提案できた日」だけを記録する）。
    /// これにより、ユーザーがあとで下書きを消しても、その日はもう提案し直さない
    /// （消した＝要らない、というユーザーの意思を尊重する）。一方、地名が分からず提案できなかった日は
    /// 記録しないので、次にアプリを開いたときにもう一度試せる。
    private static let autoFilledDefaultsKey = "locationDiaryAutoFilledDateKeys"

    private let manager: CLLocationManager
    private let geocoder = CLGeocoder()
    private let store: LocationVisitStore
    private let defaults: UserDefaults

    init(store: LocationVisitStore = .shared, defaults: UserDefaults = .standard, manager: CLLocationManager = CLLocationManager()) {
        self.store = store
        self.defaults = defaults
        self.manager = manager
        super.init()
        self.manager.delegate = self
    }

    /// 権限の状態（設定画面の表示用）。
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// アプリ起動時・設定のトグルを変えたときに呼ぶ。設定に合わせて監視を開始・停止する。
    func applySetting(enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
            store.removeAll()
        }
    }

    private func start() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startMonitoringSignificantLocationChanges()
        default:
            break // 拒否・制限中は何もしない(端末の設定アプリから変更してもらう)。
        }
    }

    private func stop() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
            guard LocationDiarySettings.isEnabled(defaults: self.defaults) else { return }
            self.manager.startMonitoringSignificantLocationChanges()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let sample = LocationVisitSample(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        Task { @MainActor [weak self] in
            self?.store.add(sample)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 取得できないときは、無理に何も表示しないという方針に合わせて静かに無視する。
    }

    // MARK: - 提案文の生成

    /// `date`の日のデフォルトの下書きを提案する。次のいずれかならnil:
    /// 設定がオフ／すでにこの日は提案済み／その日の位置情報のサンプルが無い／地名が分からない。
    func suggestedText(for date: Date, calendar: Calendar = .current) async -> String? {
        guard LocationDiarySettings.isEnabled(defaults: defaults) else { return nil }
        let key = DailyRingSlices.dateKey(for: date, calendar: calendar)
        guard !autoFilledDateKeys().contains(key) else { return nil }

        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let daySamples = store.samples(on: date, calendar: calendar)
        guard let stay = LocationDiaryAnalyzer.longestStay(daySamples: daySamples, dayStart: dayStart, dayEnd: dayEnd) else { return nil }

        let homeKey = LocationDiaryAnalyzer.homeGridKey(samples: store.samples)
        let isHome = homeKey != nil && stay.gridKey == homeKey

        let text: String?
        if isHome {
            text = LocationDiaryAnalyzer.defaultText(placeName: nil, isHome: true)
        } else {
            let name = await reverseGeocode(latitude: stay.latitude, longitude: stay.longitude)
            text = LocationDiaryAnalyzer.defaultText(placeName: name, isHome: false)
        }

        if let text {
            markAutoFilled(key: key)
        }
        return text
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location), let placemark = placemarks.first else {
            return nil
        }
        return LocationDiaryAnalyzer.placeName(
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            name: placemark.name,
            administrativeArea: placemark.administrativeArea
        )
    }

    private func autoFilledDateKeys() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.autoFilledDefaultsKey) ?? [])
    }

    private func markAutoFilled(key: String) {
        var keys = autoFilledDateKeys()
        keys.insert(key)
        defaults.set(Array(keys), forKey: Self.autoFilledDefaultsKey)
    }
}
