import Foundation

/// 網絡資料各自載入；每個來源失敗時獨立使用有效快取。
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
    var regional: RegionalConditions? = nil
    var sun: SunTimes? = nil
    var warningsFetchedAt: Date? = nil

    func currentWarnings(at now: Date) -> [WeatherWarning]? {
        guard let warningsFetchedAt, warningsFetchedAt <= now,
              now.timeIntervalSince(warningsFetchedAt) < Self.liveMaxAge else { return nil }
        return warnings
    }

    func currentTrain(at now: Date) -> TrainStatus? {
        guard let train, train.fetchedAt <= now,
              now.timeIntervalSince(train.fetchedAt) < Self.liveMaxAge else { return nil }
        return train
    }

    static let sample = ExtraInfo(
        weather: .sample, gold: .sample, latestOS: "27.0.2", updatedAt: Date(),
        warnings: [WeatherWarning(text: "黃色暴雨", severe: false)], train: .sample, air: .sample, fx: .sample,
        regional: .sample, sun: .sample, warningsFetchedAt: Date()
    )

    /// 唔使網絡：讀返上次快取。
    static func cached(now: Date = Date()) -> ExtraInfo {
        ExtraInfo(
            weather: HKOWeather.snapshot(
                current: DataCache.fresh(HKOCurrentWeather.self, key: HKOWeather.currentCacheKey, maxAge: environmentMaxAge, now: now),
                forecast: DataCache.fresh(HKOForecast.self, key: HKOWeather.forecastCacheKey, maxAge: forecastMaxAge, now: now)),
            gold: DataCache.load(GoldQuote.self, key: "gold"),
            latestOS: DataCache.load(String.self, key: "latestOS"),
            updatedAt: now,
            warnings: DataCache.fresh([WeatherWarning].self, key: "warnings", maxAge: liveMaxAge, now: now),
            train: DataCache.fresh(TrainStatus.self, key: "train", maxAge: liveMaxAge, now: now),
            air: DataCache.fresh(AirQuality.self, key: EPDAQHI.cacheKey, maxAge: environmentMaxAge, now: now),
            fx: DataCache.load(ExchangeRates.self, key: "fx"),
            regional: RegionalConditions.merged(
                wind: DataCache.fresh(RegionalConditions.self, key: HKORegional.windCacheKey, maxAge: environmentMaxAge, now: now),
                pressure: DataCache.fresh(RegionalConditions.self, key: HKORegional.pressureCacheKey, maxAge: environmentMaxAge, now: now)),
            sun: cachedSun(now: now), warningsFetchedAt: DataCache.savedAt("warnings")
        )
    }

    /// 警告同列車狀況係「而家」資料：超過呢段時間冇更新就唔再顯示，免得見到舊警告。
    static let liveMaxAge: TimeInterval = 30 * 60
    static let environmentMaxAge: TimeInterval = 2 * 3_600
    static let forecastMaxAge: TimeInterval = 48 * 3_600

    /// 天氣同黃金每次 reload 都重讀（「即時更新」先有用）；最新 iOS 版本 6 小時一次。
    static func load(now: Date = Date()) async -> ExtraInfo {
        async let weather = loadWeather(now: now)
        async let gold = loadGold(now: now)
        async let latestOS = loadLatestOS(now: now)
        async let warnings = loadWarnings(now: now)
        async let train = loadTrain(now: now)
        async let air = loadAir(now: now)
        async let fx = loadFX(now: now)
        async let regional = loadRegional(now: now)
        async let sun = loadSun(now: now)
        return ExtraInfo(
            weather: await weather, gold: await gold, latestOS: await latestOS, updatedAt: now,
            warnings: await warnings, train: await train, air: await air, fx: await fx,
            regional: await regional, sun: await sun, warningsFetchedAt: DataCache.savedAt("warnings")
        )
    }

    private static func loadWeather(now: Date) async -> WeatherSnapshot? {
        async let current = loadCurrentWeather(now: now)
        async let forecast = loadForecast(now: now)
        return HKOWeather.snapshot(current: await current, forecast: await forecast)
    }

    private static func loadCurrentWeather(now: Date) async -> HKOCurrentWeather? {
        do {
            let current = try HKOWeather.parseCurrent(try await Fetcher.data(from: HKOWeather.currentURL), now: now)
            DataCache.save(current, key: HKOWeather.currentCacheKey, stamped: now)
            return current
        } catch {
            return DataCache.fresh(HKOCurrentWeather.self, key: HKOWeather.currentCacheKey, maxAge: environmentMaxAge, now: now)
        }
    }

    private static func loadForecast(now: Date) async -> HKOForecast? {
        do {
            let forecast = try HKOWeather.parseForecast(try await Fetcher.data(from: HKOWeather.forecastURL), now: now)
            DataCache.save(forecast, key: HKOWeather.forecastCacheKey, stamped: now)
            return forecast
        } catch {
            return DataCache.fresh(HKOForecast.self, key: HKOWeather.forecastCacheKey, maxAge: forecastMaxAge, now: now)
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

    /// 本地快取 30 分鐘；來源為 EPD 一般監測站 AQHI。
    private static func loadAir(now: Date) async -> AirQuality? {
        if let fresh = DataCache.fresh(AirQuality.self, key: EPDAQHI.cacheKey, maxAge: 30 * 60, now: now) { return fresh }
        do {
            let air = try EPDAQHI.parse(try await Fetcher.data(from: EPDAQHI.url), now: now)
            DataCache.save(air, key: EPDAQHI.cacheKey, stamped: now)
            return air
        } catch {
            return DataCache.fresh(AirQuality.self, key: EPDAQHI.cacheKey, maxAge: environmentMaxAge, now: now)
        }
    }

    private static func loadRegional(now: Date) async -> RegionalConditions? {
        async let wind = loadWind(now: now)
        async let pressure = loadPressure(now: now)
        return RegionalConditions.merged(wind: await wind, pressure: await pressure)
    }

    private static func loadWind(now: Date) async -> RegionalConditions? {
        if let fresh = DataCache.fresh(RegionalConditions.self, key: HKORegional.windCacheKey, maxAge: 10 * 60, now: now) { return fresh }
        do {
            let wind = try HKORegional.parseWind(try await Fetcher.data(from: HKORegional.windURL), now: now)
            DataCache.save(wind, key: HKORegional.windCacheKey, stamped: now)
            return wind
        } catch {
            return DataCache.fresh(RegionalConditions.self, key: HKORegional.windCacheKey, maxAge: environmentMaxAge, now: now)
        }
    }

    private static func loadPressure(now: Date) async -> RegionalConditions? {
        if let fresh = DataCache.fresh(RegionalConditions.self, key: HKORegional.pressureCacheKey, maxAge: 10 * 60, now: now) { return fresh }
        do {
            let pressure = try HKORegional.parsePressure(try await Fetcher.data(from: HKORegional.pressureURL), now: now)
            DataCache.save(pressure, key: HKORegional.pressureCacheKey, stamped: now)
            return pressure
        } catch {
            return DataCache.fresh(RegionalConditions.self, key: HKORegional.pressureCacheKey, maxAge: environmentMaxAge, now: now)
        }
    }

    private static func cachedSun(now: Date) -> SunTimes? {
        let year = HKODate.calendar.component(.year, from: now)
        return DataCache.load(HKOSolarYear.self, key: HKOSolar.cacheKey(year: year))?.day(on: now)
    }

    private static func loadSun(now: Date) async -> SunTimes? {
        let year = HKODate.calendar.component(.year, from: now)
        let key = HKOSolar.cacheKey(year: year)
        if let cached = DataCache.fresh(HKOSolarYear.self, key: key, maxAge: 7 * 86_400, now: now),
           let day = cached.day(on: now) { return day }
        do {
            let annual = try HKOSolar.parse(try await Fetcher.data(from: HKOSolar.url(year: year)), year: year, now: now)
            DataCache.save(annual, key: key, stamped: now)
            return annual.day(on: now)
        } catch {
            return cachedSun(now: now)
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
