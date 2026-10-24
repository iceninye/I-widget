import Foundation

/// iOS 冇公開「剩餘使用時間」API，所以 widget 每次 reload 記低一個電量樣本，
/// 用最近一段冇充電嘅樣本計耗電速度，再推算剩幾耐。充電時就推算幾耐充滿。
struct BatterySample: Codable, Equatable {
    var time: Date
    var level: Double
    var charging: Bool
}

enum BatteryEstimate: Equatable {
    /// 剩餘秒數（放電中）。
    case remaining(TimeInterval)
    /// 充滿所需秒數（充電中）。
    case untilFull(TimeInterval)
    /// 已充滿或者接近充滿。
    case full
    /// 樣本未夠（啱啱拔電、啱啱開始充電）。
    case learning
    case unknown
}

enum BatteryHistory {
    /// 最少要隔幾耐、跌（或升）幾多先計，避免 1% 跳動令估算亂跳。
    static let minimumSpan: TimeInterval = 40 * 60
    static let minimumChange = 0.03
    /// 只睇最近 6 小時，反映而家嘅用法。
    static let window: TimeInterval = 6 * 3_600
    static let keep: TimeInterval = 24 * 3_600
    static let maxSamples = 120

    /// 加入新樣本：同上一個樣本相隔唔夠 5 分鐘就取代佢，並刪走 24 小時前嘅。
    static func appending(_ sample: BatterySample, to samples: [BatterySample]) -> [BatterySample] {
        var result = samples.filter { sample.time.timeIntervalSince($0.time) < keep && $0.time <= sample.time }
        if let last = result.last, sample.time.timeIntervalSince(last.time) < 5 * 60, last.charging == sample.charging {
            result.removeLast()
        }
        result.append(sample)
        return Array(result.suffix(maxSamples))
    }

    /// 最近一段同一狀態嘅樣本計出嚟嘅電量變化速度（每秒，正數 = 放電時跌／充電時升）。樣本未夠就 nil。
    static func rate(_ samples: [BatterySample], now: Date) -> Double? {
        guard let last = samples.last else { return nil }
        // 最近一段同一狀態（全部充電或者全部冇充電）嘅樣本
        var segment: [BatterySample] = []
        for sample in samples.reversed() {
            guard sample.charging == last.charging, now.timeIntervalSince(sample.time) <= window else { break }
            segment.insert(sample, at: 0)
        }
        guard let first = segment.first, segment.count >= 2 else { return nil }
        let span = last.time.timeIntervalSince(first.time)
        let change = last.charging ? last.level - first.level : first.level - last.level
        guard span >= minimumSpan, change >= minimumChange else { return nil }
        return change / span
    }

    /// 每小時變化幾多個百分點（例如 6.5 = 每小時 6.5%）。
    static func percentPerHour(_ samples: [BatterySample], now: Date) -> Double? {
        rate(samples, now: now).map { $0 * 3_600 * 100 }
    }

    static func estimate(_ samples: [BatterySample], now: Date) -> BatteryEstimate {
        guard let last = samples.last else { return .unknown }
        if last.charging && last.level >= 0.995 { return .full }
        guard let perSecond = rate(samples, now: now) else { return .learning }
        if last.charging {
            return .untilFull(min((1 - last.level) / perSecond, 24 * 3_600))
        }
        // 由最後一個樣本到而家已經用咗嘅時間都要扣
        let left = last.level / perSecond - max(0, now.timeIntervalSince(last.time))
        return .remaining(min(max(left, 0), 99 * 3_600))
    }

    static func text(_ estimate: BatteryEstimate) -> String? {
        switch estimate {
        case .remaining(let seconds): return "約剩 \(duration(seconds))"
        case .untilFull(let seconds): return "約 \(duration(seconds)) 充滿"
        case .full: return "已充滿"
        case .learning: return "估算中"
        case .unknown: return nil
        }
    }

    /// 「5 小時 20 分」、「45 分」、「2 日 3 小時」。
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) 分" }
        let hours = minutes / 60
        if hours >= 48 { return "\(hours / 24) 日 \(hours % 24) 小時" }
        let rest = minutes % 60
        return rest == 0 || hours >= 10 ? "\(hours) 小時" : "\(hours) 小時 \(rest) 分"
    }
}
