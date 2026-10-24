import CoreLocation
import Foundation

/// 要靠網絡或者定位先有嘅資料：天氣、黃金、最新 iOS 版本。每項各自失敗各自用快取。
struct ExtraInfo {
    var weather: WeatherSnapshot?
    var gold: GoldQuote?
    var latestOS: String?
    var updatedAt: Date
    /// nil = 讀唔到（唔係「冇警告」）
    var warnings: [WeatherWarning]?
    var train: TrainStatus?
    var air: AirQuality?
    var fx: ExchangeRates?

    static let sample = ExtraInfo(
        weather: .sample, gold: .sample, latestOS: "27.0.2", updatedAt: Date(),
        warnings: [WeatherWarning(text: "黃色暴雨", severe: false)], train: .sample, air: .sample, fx: .sample
    )

    /// 唔使網絡：讀返上次快取。
    static func cached(now: Date = Date()) -> ExtraInfo {
        ExtraInfo(
            weather: DataCache.load(WeatherSnapshot.self, key: "weather"),
            gold: DataCache.load(GoldQuote.self, key: "gold"),
            latestOS: DataCache.load(String.self, key: "latestOS"),
            updatedAt: now,
            warnings: DataCache.fresh([WeatherWarning].self, key: "warnings", maxAge: liveMaxAge, now: now),
            train: DataCache.fresh(TrainStatus.self, key: "train", maxAge: liveMaxAge, now: now),
            air: DataCache.load(AirQuality.self, key: "air"),
            fx: DataCache.load(ExchangeRates.self, key: "fx")
        )
    }

    /// 警告同列車狀況係「而家」資料：超過呢段時間冇更新就唔再顯示，免得見到舊警告。
    static let liveMaxAge: TimeInterval = 30 * 60

    /// 天氣同黃金每次 reload 都重讀（「即時更新」先有用）；最新 iOS 版本 6 小時一次。
    static func load(now: Date = Date()) async -> ExtraInfo {
        async let weather = loadWeather(now: now)
        async let gold = loadGold(now: now)
        async let latestOS = loadLatestOS(now: now)
        async let warnings = loadWarnings(now: now)
        async let train = loadTrain(now: now)
        async let air = loadAir(now: now)
        async let fx = loadFX(now: now)
        return ExtraInfo(
            weather: await weather, gold: await gold, latestOS: await latestOS, updatedAt: now,
            warnings: await warnings, train: await train, air: await air, fx: await fx
        )
    }

    private static func loadWeather(now: Date) async -> WeatherSnapshot? {
        let coordinate = await WidgetLocation.coordinate()
        do {
            guard let url = OpenMeteo.url(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
                throw URLError(.badURL)
            }
            let snapshot = try OpenMeteo.parse(try await Fetcher.data(from: url), now: now)
            DataCache.save(snapshot, key: "weather")
            return snapshot
        } catch {
            return DataCache.load(WeatherSnapshot.self, key: "weather")
        }
    }

    private static func loadGold(now: Date) async -> GoldQuote? {
        do {
            let quote = try GoldAPI.parse(try await Fetcher.data(from: GoldAPI.url), now: now)
            DataCache.save(quote, key: "gold")
            return quote
        } catch {
            return DataCache.load(GoldQuote.self, key: "gold")
        }
    }

    private static func loadWarnings(now: Date) async -> [WeatherWarning]? {
        do {
            let warnings = try HKOWarnings.parse(try await Fetcher.data(from: HKOWarnings.url))
            DataCache.save(warnings, key: "warnings", stamped: now)
            return warnings
        } catch {
            return DataCache.fresh([WeatherWarning].self, key: "warnings", maxAge: liveMaxAge, now: now)
        }
    }

    private static func loadTrain(now: Date) async -> TrainStatus? {
        do {
            let status = try MTRStatus.parse(try await Fetcher.data(from: MTRStatus.url), now: now)
            DataCache.save(status, key: "train", stamped: now)
            return status
        } catch {
            return DataCache.fresh(TrainStatus.self, key: "train", maxAge: liveMaxAge, now: now)
        }
    }

    /// 空氣質素 30 分鐘一次。
    private static func loadAir(now: Date) async -> AirQuality? {
        if let fresh = DataCache.fresh(AirQuality.self, key: "air", maxAge: 30 * 60, now: now) { return fresh }
        let coordinate = await WidgetLocation.coordinate()
        do {
            guard let url = OpenMeteoAir.url(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
                throw URLError(.badURL)
            }
            let air = try OpenMeteoAir.parse(try await Fetcher.data(from: url), now: now)
            DataCache.save(air, key: "air", stamped: now)
            return air
        } catch {
            return DataCache.load(AirQuality.self, key: "air")
        }
    }

    /// 匯率每日更新一次，6 小時讀一次已經夠。
    private static func loadFX(now: Date) async -> ExchangeRates? {
        if let fresh = DataCache.fresh(ExchangeRates.self, key: "fx", maxAge: 6 * 3_600, now: now) { return fresh }
        do {
            let rates = try FXAPI.parse(try await Fetcher.data(from: FXAPI.url), now: now)
            DataCache.save(rates, key: "fx", stamped: now)
            return rates
        } catch {
            return DataCache.load(ExchangeRates.self, key: "fx")
        }
    }

    private static func loadLatestOS(now: Date) async -> String? {
        let checkedAt = DataCache.load(Date.self, key: "latestOSChecked")
        if let checkedAt, now.timeIntervalSince(checkedAt) < 6 * 3_600,
           let cached = DataCache.load(String.self, key: "latestOS") {
            return cached
        }
        do {
            let latest = try OSVersion.parseLatest(try await Fetcher.data(from: OSVersion.latestURL))
            DataCache.save(latest, key: "latestOS")
            DataCache.save(now, key: "latestOSChecked")
            return latest
        } catch {
            return DataCache.load(String.self, key: "latestOS")
        }
    }
}

struct SavedCoordinate: Codable {
    var latitude: Double
    var longitude: Double
}

/// 取一次大約位置。未授權、逾時、失敗就用上次位置，再冇就用香港市區。
enum WidgetLocation {
    static let fallback = SavedCoordinate(latitude: 22.3193, longitude: 114.1694)

    static func coordinate() async -> SavedCoordinate {
        if let location = await OneShotLocation.current() {
            let found = SavedCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            DataCache.save(found, key: "coordinate")
            return found
        }
        return DataCache.load(SavedCoordinate.self, key: "coordinate") ?? fallback
    }
}

final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var selfReference: OneShotLocation?

    static func current(timeout: TimeInterval = 5) async -> CLLocation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let helper = OneShotLocation()
                helper.continuation = continuation
                helper.start(timeout: timeout)
            }
        }
    }

    private func start(timeout: TimeInterval) {
        let status = manager.authorizationStatus
        let authorised = manager.isAuthorizedForWidgetUpdates || status == .authorizedWhenInUse || status == .authorizedAlways
        guard authorised else {
            finish(manager.location)
            return
        }
        selfReference = self
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.finish(self.manager.location)
        }
    }

    private func finish(_ location: CLLocation?) {
        guard let continuation else { return }
        self.continuation = nil
        selfReference = nil
        continuation.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(manager.location)
    }
}
