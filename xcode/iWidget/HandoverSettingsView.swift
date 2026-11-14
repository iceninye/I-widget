import AVFoundation
import SwiftUI

/// 交接提示嘅詳細設定：每種情況提前幾耐、語音、試聲，同將會響嘅提示預覽。
/// 改完即刻儲存，停手 1 秒後用手上嘅更份資料重排（唔使再上網）。
struct HandoverSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var settings = HandoverSettings.load()
    @State private var upcoming: [HandoverAlert] = []
    @State private var spoken = 0
    @State private var message = ""
    @State private var testing = false
    @AppStorage(DutyActivityManager.enabledKey) private var countdownEnabled = false
    @AppStorage(DutyActivityManager.leadKey) private var countdownLead = DutyActivityPlan.defaultLeadMinutes

    private static let leads = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120]
    private static let sample = "15 分鐘後你要喺錦上路 2接 128 更嘅 Run 18，開去烏溪沙"

    var body: some View {
        Form {
            Section {
                lead("上班前（第一次）", $settings.onFirst)
                lead("上班前（第二次）", $settings.onSecond)
                lead("接車前", $settings.pickUp)
                lead("落地／交車前", $settings.dropOff)
                lead("用膳完結前", $settings.mealEnd)
                lead("最後一次落地前", $settings.lastDrop)
                lead("放工前", $settings.off)
            } header: {
                Text("提前幾耐提")
            } footer: {
                Text("「用膳完結前」係用膳後第一程接車嘅提示。每個提示都會講埋之後做咩（用膳、泊車、接另一架車、收工）。")
            }

            Section {
                Toggle("讀出提示", isOn: $settings.speak)
                if settings.speak {
                    Picker("聲線", selection: $settings.voice) {
                        Text("自動（廣東話）").tag(String?.none)
                        ForEach(SpokenSound.voices(), id: \.identifier) { voice in
                            Text(Self.voiceName(voice)).tag(String?.some(voice.identifier))
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("語速")
                        Slider(value: $settings.rate, in: 0.35...0.6, step: 0.05) {
                            Text("語速")
                        } minimumValueLabel: {
                            Text("慢").font(.footnote)
                        } maximumValueLabel: {
                            Text("快").font(.footnote)
                        }
                    }
                    Toggle("讀兩次", isOn: $settings.twice)
                }
                Button("試聽") {
                    run {
                        let played = await SpokenSound.preview(Self.sample, settings: settings)
                        return played ? "" : "錄唔到語音：睇吓 iPhone 有冇廣東話聲線（設定 →「輔助使用」→「朗讀內容」→「聲音」→ 中文）。"
                    }
                }
                .disabled(testing || !settings.speak)
                Button("5 秒後發測試通知") {
                    run {
                        guard await HandoverNotifier.requestAuthorization() else { return "未允許通知：去 iPhone 設定 →「通知」→ i-widget 開啟。" }
                        let voiced = await HandoverNotifier.test(Self.sample, settings: settings)
                        return voiced || !settings.speak ? "已排測試通知，5 秒後響。" : "已排測試通知，但錄唔到語音，會用預設提示聲。"
                    }
                }
                .disabled(testing)
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("語音")
            } footer: {
                Text("""
                「試聽」唔受靜音掣影響；通知就同其他通知一樣：開咗靜音掣、專注模式，或者鈴聲音量校到好細，就聽唔到。
                試聽有聲但測試通知冇聲：睇吓靜音掣、控制中心嘅專注模式，同 iPhone 設定 →「通知」→ i-widget →「聲音」。
                想把聲自然啲：iPhone 設定 →「輔助使用」→「朗讀內容」→「聲音」→ 中文（粵語）下載「高音質」，再喺上面揀返。
                """)
            }

            Section {
                Toggle("開 app 或者排提示時更新倒數", isOn: $countdownEnabled)
                Picker("下一件事前幾耐開始顯示", selection: $countdownLead) {
                    ForEach([60, 120, 180, 240, 360], id: \.self) { minutes in
                        Text("\(minutes / 60) 小時前").tag(minutes)
                    }
                }
                Button("而家開始／更新倒數") {
                    run { await DutyActivityManager.sync(events: model.entry.schedule.dutyEvents(now: Date())) }
                }
                .disabled(testing)
                Button("結束倒數", role: .destructive) {
                    run {
                        await DutyActivityManager.endAll()
                        return "已結束倒數。"
                    }
                }
                .disabled(testing)
            } header: {
                Text("更份倒數（鎖定畫面）")
            } footer: {
                Text("""
                鎖定畫面同動態島顯示下一件事（返工、接車、落地、放工）嘅倒數，加之後兩件事。倒數數字由系統自己跳；內容只會喺開 app、捷徑執行時更新（免費簽名冇 push）。
                捷徑 App →「自動化」→「個人」→ 返工前幾個鐘同之後每 2 小時左右 → 動作「更新更份倒數」→ 揀「立即執行」。下一件事前幾耐先出現跟上面嘅設定；Live Activity 最長 8 小時，行咗超過 6 小時會自動開新嘅。
                倒數去到零之後會顯示「待更新」，唔會再列之後嘅事，直到下一次更新。「之後」清單係上次同步嘅快照，唔識逐項自動消失。撳鎖定畫面倒數會開啟 app「資料」頁並更新；就算熄咗上面嘅自動更新開關，手動開始而又仲行緊嘅倒數都會更新。
                """)
            }

            Section {
                if upcoming.isEmpty {
                    Text("今日同明日冇提示（休息、已經放工，或者未填 token）。").foregroundStyle(.secondary)
                }
                ForEach(upcoming, id: \.id) { alert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Self.clock(alert.fireAt)) 響 · \(alert.title)").font(.subheadline.weight(.semibold))
                        Text(alert.body).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("將會響嘅提示（\(upcoming.count) 個）")
            } footer: {
                if HandoverNotifier.isEnabled {
                    Text(settings.speak ? "有 \(spoken) 個錄好咗語音，其餘用預設提示聲。" : "全部用預設提示聲。")
                } else {
                    Text("「交接提示」未開，呢度只係預覽。")
                }
            }
        }
        .navigationTitle("提示設定")
        .navigationBarTitleDisplayMode(.inline)
        // 改設定：即刻存，停手 1 秒先重排（錄音要時間）
        .task(id: settings) {
            settings.save()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            upcoming = await model.rescheduleHandover()
            spoken = UserDefaults.standard.integer(forKey: HandoverNotifier.lastSpokenKey)
        }
    }

    private func lead(_ title: String, _ value: Binding<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(Self.options(including: value.wrappedValue), id: \.self) { minutes in
                Text(Self.leadName(minutes)).tag(minutes)
            }
        }
    }

    private func run(_ work: @escaping @MainActor () async -> String) {
        testing = true
        message = ""
        Task { @MainActor in
            message = await work()
            testing = false
        }
    }

    private static func options(including value: Int) -> [Int] {
        leads.contains(value) ? leads : (leads + [value]).sorted()
    }

    private static func leadName(_ minutes: Int) -> String {
        if minutes == 0 { return "唔提" }
        if minutes < 60 { return "\(minutes) 分鐘前" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小時前" : "\(minutes / 60) 小時 \(minutes % 60) 分鐘前"
    }

    private static func voiceName(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name)（最高音質）"
        case .enhanced: return "\(voice.name)（高音質）"
        default: return voice.name
        }
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}
