import CoreLocation
import Foundation

/// 要靠網絡或者定位先有嘅資料：天氣、黃金、最新 iOS 版本。每項各自失敗各自用快取。
struct ExtraInfo {
    var weather: WeatherSnapshot?
    var gold: GoldQuote?
    var latestOS: String?
    var updatedAt: Date

    static let sample = ExtraInfo(weather: .sample, gold: .sample, latestOS: "27.0.2", updatedAt: Date())

    /// 唔使網絡：讀返上次快取。
    static func cached(now: Date = Date()) -> ExtraInfo {
        ExtraInfo(
            weather: DataCache.load(WeatherSnapshot.self, key: "weather"),
            gold: DataCache.load(GoldQuote.self, key: "gold"),
            latestOS: DataCache.load(String.self, key: "latestOS"),
            updatedAt: now
        )
    }

    /// 天氣同黃金每次 reload 都重讀（「即時更新」先有用）；最新 iOS 版本 6 小時一次。
    static func load(now: Date = Date()) async -> ExtraInfo {
        async let weather = loadWeather(now: now)
        async let gold = loadGold(now: now)
        async let latestOS = loadLatestOS(now: now)
        return ExtraInfo(weather: await weather, gold: await gold, latestOS: await latestOS, updatedAt: now)
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
