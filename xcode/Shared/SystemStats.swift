import Foundation
import UIKit

/// 一次讀取嘅系統狀態。Widget extension 同 app 共用。
struct SystemStats: Equatable {
    var batteryLevel: Double?   // 0...1；讀唔到 = nil
    var isCharging: Bool
    var isFullyCharged: Bool
    var isLowPowerMode: Bool
    var freeBytes: Int64?
    var totalBytes: Int64?
    /// 開機時刻。開機時間 = 顯示嗰刻 − bootDate，所以 timeline 每個 entry 都準確（包括睡眠時間）。
    var bootDate: Date?
    var systemName: String
    var systemVersion: String

    var versionText: String { "\(systemName) \(systemVersion)" }

    func uptime(at date: Date) -> TimeInterval? {
        bootDate.map { date.timeIntervalSince($0) }
    }

    static let sample = SystemStats(
        batteryLevel: 0.75,
        isCharging: false,
        isFullyCharged: false,
        isLowPowerMode: true,
        freeBytes: 32_600_000_000,
        totalBytes: 255_400_000_000,
        bootDate: Date(timeIntervalSinceNow: -(23 * 86_400 + 18 * 3_600)),
        systemName: "iOS",
        systemVersion: "27.0.1"
    )

    static func read() -> SystemStats {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let rawLevel = Double(device.batteryLevel)          // -1 = 讀唔到
        let state = device.batteryState

        let (free, total) = readStorage()

        return SystemStats(
            batteryLevel: rawLevel >= 0 ? min(rawLevel, 1) : nil,
            isCharging: state == .charging,
            isFullyCharged: state == .full,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            freeBytes: free,
            totalBytes: total,
            bootDate: readBootDate(),
            systemName: device.systemName,
            systemVersion: device.systemVersion
        )
    }

    /// 同「設定 → 一般 → iPhone 儲存空間」一樣（計埋可清除空間）。
    private static func readStorage() -> (Int64?, Int64?) {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? home.resourceValues(forKeys: keys) else { return (nil, nil) }
        let free = values.volumeAvailableCapacityForImportantUsage
        let total = values.volumeTotalCapacity.map { Int64($0) }
        return (free, total)
    }

    /// `kern.boottime`：真正開機時刻（`systemUptime` 唔計睡眠時間）。
    private static func readBootDate() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, UInt32(mib.count), &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
