import CoreLocation
import Foundation

/// 要靠網絡或者定位先有嘅資料：天氣、黃金、最新 iOS 版本。每項各自失敗各自用快取。
struct ExtraInfo {
    var weather: WeatherSnapshot?
    var gold: GoldQuote?
    var latestOS: String?
    /// 全部來源（唔分 widget）之中，最後成功取得其中一項資料嘅時間；一個來源都冇成功記錄就 nil
    /// （即係「未有資料」，唔係「啱啱更新」）。fall back 舊快取時唔會翻新呢個時間。
    /// app 內預覽用呢個；widget 標題要用自己範圍嘅 `todayUpdatedAt`／`infoUpdatedAt`，
    /// 否則今日咭會顯示「各項資訊」啱啱讀嘅時間、反之亦然（互相灌水）。
    var updatedAt: Date?
    /// nil = 讀唔到（唔係「冇警告」）
    var warnings: [WeatherWarning]?
    var train: TrainStatus?
    var air: AirQuality?
    var fx: ExchangeRates?
    /// 天氣警告**各範圍自己**嘅最後成功時間（`Freshness.warningsKey(.today)`／`.info`，
    /// 新 key 冇記錄就退回升級前嘅共用 key）。警告係兩個 widget 都會畫嘅同一份資料，
    /// 但成功時間必須分範圍記，否則今日咭會拿「各項資訊」啱啱成功嘅時間冒充自己（反之亦然）。
    /// 呢個字典只喺快取讀、唔喺呢度寫：用 fallback 時照用舊時間，唔會翻新（規則喺 `Freshness`）。
    /// 放喺最後一個欄位：前邊嘅欄位順序唔變，`sample`／各 init 呼叫位照用 label 順序。
    var warningsStamps: [Freshness.Scope: Date] = [:]

    static let sample = ExtraInfo(
        weather: .sample, gold: .sample, latestOS: "27.0.2", updatedAt: Date(),
        warnings: [WeatherWarning(text: "黃色暴雨", severe: false)], train: .sample, air: .sample, fx: .sample,
        warningsStamps: [.today: Date(), .info: Date()]
    )

    /// 唔使網絡：讀返上次快取。
    /// `part` = 邊個 widget（決定攞邊個範圍嘅天氣警告）；唔傳係 app 內預覽（唔分 widget，兩份揀較新嗰份）。
    static func cached(now: Date = Date(), part: OverviewPart? = nil) -> ExtraInfo {
        let warnings = cachedWarnings(scopes: part.map { [$0.warningsScope] } ?? Freshness.Scope.allCases, now: now)
        var info = ExtraInfo(
            weather: DataCache.load(WeatherSnapshot.self, key: "weather"),
            gold: DataCache.load(GoldQuote.self, key: "gold"),
            latestOS: DataCache.load(String.self, key: "latestOS"),
            updatedAt: nil,
            warnings: warnings,
            train: DataCache.fresh(TrainStatus.self, key: "train", maxAge: liveMaxAge, now: now),
            air: DataCache.load(AirQuality.self, key: "air"),
            fx: DataCache.load(ExchangeRates.self, key: "fx")
        )
        info.warningsStamps = cachedWarningsStamps()
        info.updatedAt = lastSuccess(of: info)
        return info
    }

    // MARK: 天氣警告：資料同「成功時間」都按 widget 範圍分開

    /// 分範圍嘅警告成功時間（只讀快取，唔寫入，所以唔會翻新）。
    private static func cachedWarningsStamps() -> [Freshness.Scope: Date] {
        var stamps: [Freshness.Scope: Date] = [:]
        for scope in Freshness.Scope.allCases {
            if let at = warningsStamp(scope) { stamps[scope] = at }
        }
        return stamps
    }

    /// 某範圍警告嘅最後成功時間：自己嗰份優先，冇就退回升級前共用 key（舊裝置唔會變「讀唔到」）。
    /// fallback 唔會翻新：得返舊記錄就照舊，唔會因為又試咗一次就變「啱啱更新」。
    private static func warningsStamp(_ scope: Freshness.Scope) -> Date? {
        Freshness.stamp(
            current: DataCache.savedAt(Freshness.warningsKey(scope)),
            fallback: DataCache.savedAt(Freshness.legacyWarningsKey)
        )
    }

    /// 警告資料（唔使上網）：逐個範圍試（成功時間較新嗰份先），自己嗰份冇就退回升級前共用 key。
    /// 超過 `liveMaxAge` 一樣當讀唔到（nil），唔係「冇警告」。
    private static func cachedWarnings(scopes: [Freshness.Scope], now: Date) -> [WeatherWarning]? {
        for scope in scopes.sorted(by: { (warningsStamp($0) ?? .distantPast) > (warningsStamp($1) ?? .distantPast) }) {
            if let warnings = cachedWarnings(scope: scope, now: now) { return warnings }
        }
        return nil
    }

    private static func cachedWarnings(scope: Freshness.Scope, now: Date) -> [WeatherWarning]? {
        DataCache.fresh([WeatherWarning].self, key: Freshness.warningsKey(scope), maxAge: liveMaxAge, now: now)
            ?? DataCache.fresh([WeatherWarning].self, key: Freshness.legacyWarningsKey, maxAge: liveMaxAge, now: now)
    }

    /// 各來源自己嘅成功時間（模型內嘅 `fetchedAt`，或者只有快取有時間嘅來源用 `DataCache.savedAt`）取最新一個；
    /// 全部冇記錄就 nil。用快取 fallback 時會攞到舊時間，唔會當做啱啱更新。
    /// 呢個係「唔分 widget」嘅全 app 口徑（`updatedAt`）；widget 用下面兩個分範圍嘅版本。
    private static func lastSuccess(of info: ExtraInfo) -> Date? { info.freshnessSources().overallStamp }

    /// 自己各來源嘅成功時間，交俾 `Freshness.Sources` 分口徑取「最後任一相關來源成功」。
    /// 更份／學校日曆同 VPS 唔喺呢度（由 `OverviewEntry` 補）；警告用 `warningsStamps` 自己嘅時間，
    /// 唔攞其他來源嘅時間，所以對方 widget 啱啱成功唔會灌水自己呢邊。
    func freshnessSources() -> Freshness.Sources {
        Freshness.Sources(
            weather: weather?.fetchedAt,
            warningsToday: warningsStamps[.today],
            warningsInfo: warningsStamps[.info],
            train: train?.fetchedAt,
            gold: gold?.fetchedAt,
            air: air?.fetchedAt,
            fx: fx?.fetchedAt,
            latestOS: DataCache.savedAt("latestOS")
        )
    }

    // MARK: 按 widget 分範圍嘅「最後任一相關來源成功」時間
    //
    // 呢啲係「相關來源入面最遲成功嗰個」，唔係「全部來源都成功」；某個來源一直失敗、
    // 另一個來源成功，都會顯示成功嗰個嘅時間。
    // 來源範圍嘅定義喺 `Freshness.Sources`（純邏輯、有測試）。

    /// 今日咭畫嘅來源：天氣、天氣警告（**today 範圍**嗰份）、屯馬綫；更份／學校日曆由 `OverviewEntry` 補。
    /// 唔計黃金／空氣／匯率／最新系統版本——呢啲由「各項資訊」widget 更新，計入嚟會令今日咭嘅更新時間灌水。
    var todayUpdatedAt: Date? { freshnessSources().todayStamp }

    /// 「各項資訊」畫嘅來源：天氣、天氣警告（**info 範圍**嗰份）、屯馬綫、黃金、空氣、匯率、最新系統版本。
    /// 唔計更份／學校日曆（呢啲由今日咭更新）；VPS 嘅時間喺 `OverviewEntry` 嗰邊補。
    var infoUpdatedAt: Date? { freshnessSources().infoStamp }

    /// 警告同列車狀況係「而家」資料：超過呢段時間冇更新就唔再顯示，免得見到舊警告。
    static let liveMaxAge: TimeInterval = 30 * 60

    /// 天氣同黃金每次 reload 都重讀（「即時更新」先有用）；最新 iOS 版本 6 小時一次。
    /// 警告記入「各項資訊」範圍（app 內刷新都算呢邊，因為畫警告嘅 app 頁同資訊 widget 同一組來源）。
    static func load(now: Date = Date()) async -> ExtraInfo {
        async let weather = loadWeather(now: now)
        async let gold = loadGold(now: now)
        async let latestOS = loadLatestOS(now: now)
        async let warnings = loadWarnings(scope: .info, now: now)
        async let train = loadTrain(now: now)
        async let air = loadAir(now: now)
        async let fx = loadFX(now: now)
        var info = ExtraInfo(
            weather: await weather, gold: await gold, latestOS: await latestOS, updatedAt: nil,
            warnings: await warnings, train: await train, air: await air, fx: await fx
        )
        // 成功時間喺寫入快取之後先讀返：本次成功就係本次時間，本次失敗就照用快取嘅舊時間
        info.warningsStamps = cachedWarningsStamps()
        info.updatedAt = lastSuccess(of: info)
        return info
    }

    /// 今日咭：天氣（10 分鐘內讀過就用返）、天氣警告、屯馬綫；其餘（黃金、匯率等）用快取。
    /// 警告記入 **today 範圍**，所以資訊 widget 啱啱成功讀過警告唔會令今日咭嘅「更新於」變啱啱。
    static func loadToday(now: Date = Date()) async -> ExtraInfo {
        async let weather = loadWeather(now: now, reuseWithin: 10 * 60)
        async let warnings = loadWarnings(scope: .today, now: now)
        async let train = loadTrain(now: now)
        var info = cached(now: now, part: .today)
        info.weather = await weather
        info.warnings = await warnings
        info.train = await train
        info.warningsStamps = cachedWarningsStamps()
        info.updatedAt = lastSuccess(of: info)
        return info
    }

    /// `reuseWithin`：今日咭同資訊 widget 差唔多時間 reload，避免重複讀。
    private static func loadWeather(now: Date, reuseWithin maxAge: TimeInterval? = nil) async -> WeatherSnapshot? {
        if let maxAge, let fresh = DataCache.fresh(WeatherSnapshot.self, key: "weather", maxAge: maxAge, now: now) {
            return fresh
        }
        let coordinate = await WidgetLocation.coordinate()
        do {
            guard let url = OpenMeteo.url(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
                throw URLError(.badURL)
            }
            let snapshot = try OpenMeteo.parse(try await Fetcher.data(from: url), now: now)
            DataCache.save(snapshot, key: "weather", stamped: now)
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

    /// 讀天氣警告：成功就喺**自己範圍**嘅 key 記低本次時間；失敗就沿用該範圍嘅快取，
    /// 時間照用快取原本嗰個（`Freshness.stamp`／`warningsStamp`），唔會因為又試咗一次就翻新。
    private static func loadWarnings(scope: Freshness.Scope, now: Date) async -> [WeatherWarning]? {
        do {
            let warnings = try HKOWarnings.parse(try await Fetcher.data(from: HKOWarnings.url))
            DataCache.save(warnings, key: Freshness.warningsKey(scope), stamped: now)
            return warnings
        } catch {
            return cachedWarnings(scope: scope, now: now)
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
        if let fresh = DataCache.fresh(String.self, key: "latestOS", maxAge: 6 * 3_600, now: now) { return fresh }
        do {
            let latest = try OSVersion.parseLatest(try await Fetcher.data(from: OSVersion.latestURL))
            DataCache.save(latest, key: "latestOS", stamped: now)
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
