import Foundation

/// 撳資料格會反轉去背面睇更多資料；反轉咗嘅格過一陣自動轉返正面。
/// 純邏輯：存放同 widget 刷新喺 extension 入面做。
struct FlipState: Codable, Equatable {
    static let duration: TimeInterval = 90

    /// 格 id → 反轉嗰刻
    var flipped: [String: Date] = [:]

    func isFlipped(_ id: String, at date: Date) -> Bool {
        guard let start = flipped[id] else { return false }
        return date >= start && date < start.addingTimeInterval(Self.duration)
    }

    mutating func toggle(_ id: String, now: Date) {
        prune(now: now)
        if isFlipped(id, at: now) {
            flipped[id] = nil
        } else {
            flipped[id] = now
        }
    }

    mutating func prune(now: Date) {
        flipped = flipped.filter { now < $0.value.addingTimeInterval(Self.duration) }
    }

    /// 之後自動轉返正面嘅時間，timeline 用嚟加 entry。
    func expiries(after now: Date) -> [Date] {
        flipped.values.map { $0.addingTimeInterval(Self.duration) }.filter { $0 > now }.sorted()
    }
}
