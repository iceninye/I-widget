import SwiftUI
import WidgetKit

@main
struct IWidgetBundle: WidgetBundle {
    var body: some Widget {
        IWidget()
        ScheduleWidget()
        VPSWidget()
    }
}

struct IWidget: Widget {
    let kind = "IWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            StatsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("i-widget")
        .description("時間、電量、儲存空間、開機時間同系統版本。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
        ])
    }
}
