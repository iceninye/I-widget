import AVFoundation
import Foundation

/// 將提示句子用 iPhone 語音合成（廣東話）錄成 `Library/Sounds/handover-*.caf`，做通知提示聲：
/// 通知一響就由手機喇叭讀出，唔使 AirPods／CarPlay。靜音掣開咗就只會震。
/// 通知提示聲最長 30 秒，要係 Linear PCM，所以存 16-bit PCM。
enum SpokenSound {
    static let prefix = "handover-"
    /// 通知提示聲上限 30 秒，超過系統會改播預設聲
    static let maxSeconds = 29.0

    static var directory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// 檔名跟提示 id、內容同語音設定：任何一樣變咗就係新檔。
    static func fileName(id: String, text: String, settings: HandoverSettings) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        let key = "\(id)|\(text)|\(settings.voice ?? "")|\(Int(settings.rate * 100))|\(settings.twice)"
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return "\(prefix)\(String(hash, radix: 16)).caf"
    }

    /// 刪走唔喺 `keep` 入面嘅舊語音檔（已經響完、或者更表改咗）。
    static func removeAll(except keep: Set<String> = []) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file.hasPrefix(prefix) && !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// 可以揀嘅廣東話聲線（iPhone 設定 →「輔助使用」→「朗讀內容」→「聲音」可以下載高音質版）。
    static func voices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-HK" }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    static func voice(_ settings: HandoverSettings) -> AVSpeechSynthesisVoice? {
        settings.voice.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: "zh-HK")
            ?? AVSpeechSynthesisVoice(language: "zh-TW")
    }

    /// 檔案讀得返、有聲、唔超過 30 秒先算得。
    static func isUsable(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0, file.fileFormat.sampleRate > 0 else { return false }
        return Double(file.length) / file.fileFormat.sampleRate <= maxSeconds
    }

    /// 錄好（或者已經有）就回傳檔名；失敗回傳 nil，通知就用預設提示聲。
    static func make(id: String, text: String, settings: HandoverSettings) async -> String? {
        guard let directory else { return nil }
        let name = fileName(id: id, text: text, settings: settings)
        let url = directory.appendingPathComponent(name)
        if isUsable(url) { return name }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let spoken = settings.twice ? "\(text)。\(text)" : text
        let ok = await Recorder().write(spoken, voice: voice(settings), rate: Float(settings.rate), to: url)
        if ok, isUsable(url) { return name }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    @MainActor private static var player: AVAudioPlayer?

    /// 試聽：錄一次再即刻播（用「播放」類別，靜音掣開咗都聽到，方便分辨係錄音定係靜音嘅問題）。
    @MainActor
    static func preview(_ text: String, settings: HandoverSettings) async -> Bool {
        guard let name = await make(id: "preview", text: text, settings: settings),
              let url = directory?.appendingPathComponent(name) else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        return player?.play() ?? false
    }

    /// 每次錄音一個 synthesizer，錄完先釋放。
    /// 完結訊號有三個，邊個先到用邊個：空 buffer、delegate 嘅 didFinish、或者已經有聲但 1.5 秒冇新 buffer。
    /// 15 秒都未完就當失敗。
    private final class Recorder: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        private let synthesizer = AVSpeechSynthesizer()
        private let lock = NSLock()
        private var file: AVAudioFile?
        private var failed = false
        private var lastBuffer: Date?
        private var started = Date()
        private var continuation: CheckedContinuation<Bool, Never>?

        func write(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float, to url: URL) async -> Bool {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = rate
            // 開頭留少少空白，唔好一響就開口
            utterance.preUtteranceDelay = 0.2
            synthesizer.delegate = self
            return await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                started = Date()
                lock.unlock()
                watch()
                synthesizer.write(utterance) { [self] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 {
                        finish(true)
                    } else {
                        append(pcm, to: url)
                    }
                }
            }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            finish(true)
        }

        /// 每半秒睇一次：有聲之後靜咗 1.5 秒當錄完；總共 15 秒逾時。
        private func watch() {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
                lock.lock()
                let pending = continuation != nil
                let idle = lastBuffer.map { Date().timeIntervalSince($0) > 1.5 } ?? false
                let expired = Date().timeIntervalSince(started) > 15
                lock.unlock()
                guard pending else { return }
                if idle {
                    finish(true)
                } else if expired {
                    finish(false)
                } else {
                    watch()
                }
            }
        }

        private func append(_ pcm: AVAudioPCMBuffer, to url: URL) {
            lock.lock()
            defer { lock.unlock() }
            guard continuation != nil else { return }
            lastBuffer = Date()
            do {
                if file == nil {
                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: pcm.format.sampleRate,
                        AVNumberOfChannelsKey: pcm.format.channelCount,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                    ]
                    file = try AVAudioFile(
                        forWriting: url,
                        settings: settings,
                        commonFormat: pcm.format.commonFormat,
                        interleaved: pcm.format.isInterleaved
                    )
                }
                try file?.write(from: pcm)
            } catch {
                failed = true
            }
        }

        /// 只會 resume 一次。
        private func finish(_ done: Bool) {
            lock.lock()
            let pending = continuation
            continuation = nil
            let ok = done && file != nil && !failed
            // 釋放 AVAudioFile 先會寫好檔頭
            file = nil
            lock.unlock()
            guard let pending else { return }
            if !done { synthesizer.stopSpeaking(at: .immediate) }
            pending.resume(returning: ok)
        }
    }
}
