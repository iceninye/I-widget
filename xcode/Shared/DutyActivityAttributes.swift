import ActivityKit
import Foundation

/// 更份倒數 Live Activity：資料全部喺 `DutyActivityState`（會變），attributes 本身冇固定欄位。
/// app 同 widget extension 都要編入。
struct DutyActivityAttributes: ActivityAttributes {
    typealias ContentState = DutyActivityState
}
