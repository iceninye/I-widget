import SwiftUI
import WidgetKit

#Preview("小", as: .systemSmall) {
    IWidget()
} timeline: {
    StatsEntry(date: Date(), stats: .sample, info: .sample)
}

#Preview("中", as: .systemMedium) {
    IWidget()
} timeline: {
    StatsEntry(date: Date(), stats: .sample, info: .sample)
}

#Preview("大", as: .systemLarge) {
    IWidget()
} timeline: {
    StatsEntry(date: Date(), stats: .sample, info: .sample)
}

#Preview("鎖屏 長方形", as: .accessoryRectangular) {
    IWidget()
} timeline: {
    StatsEntry(date: Date(), stats: .sample, info: .sample)
}
