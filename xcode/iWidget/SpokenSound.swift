import AVFoundation
import Foundation

/// 將提示句子用 iPhone 語音合成（廣東話）錄成 `Library/Sounds/handover-*.caf`，做通知提示聲：
/// 通知一響就由手機喇叭讀出，唔使 AirPods／CarPlay。靜音掣開咗就只會震。
/// 通知提示聲最長 30 秒，要係 Linear PCM，所以存 16-bit PCM。
enum SpokenSound {
    static let prefix = "handover-"

    static var directory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// 檔名跟提示 id 同內容：內容一變就係新檔。
    static func fileName(id: String, text: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in "\(id)|\(text)".utf8 {
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

    /// 錄好（或者已經有）就回傳檔名；失敗回傳 nil，通知就用預設提示聲。
    static func make(id: String, text: String) async -> String? {
        guard let directory else { return nil }
        let name = fileName(id: id, text: text)
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ok = await Recorder().write(text, to: url)
        if ok, FileManager.default.fileExists(atPath: url.path) { return name }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    /// 每次錄音一個 synthesizer，錄完先釋放。15 秒都未錄完就當失敗。
    private final class Recorder: @unchecked Sendable {
        private let synthesizer = AVSpeechSynthesizer()
        private let lock = NSLock()
        private var file: AVAudioFile?
        private var failed = false
        private var continuation: CheckedContinuation<Bool, Never>?

        func write(_ text: String, to url: URL) async -> Bool {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-HK") ?? AVSpeechSynthesisVoice(language: "zh-TW")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            // 頭尾留少少空白，唔好一響就開口
            utterance.preUtteranceDelay = 0.2
            return await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [self] in finish(false) }
                synthesizer.write(utterance) { [self] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    // 最後一段：空 buffer 代表錄完
                    if pcm.frameLength == 0 {
                        finish(true)
                    } else {
                        append(pcm, to: url)
                    }
                }
            }
        }

        private func append(_ pcm: AVAudioPCMBuffer, to url: URL) {
            lock.lock()
            defer { lock.unlock() }
            guard continuation != nil else { return }
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

        /// 只會 resume 一次：錄完或者逾時，邊個先到就用邊個。
        private func finish(_ done: Bool) {
            lock.lock()
            let pending = continuation
            continuation = nil
            let ok = done && file != nil && !failed
            // 釋放 AVAudioFile 先會寫好檔頭
            file = nil
            lock.unlock()
            if !done { synthesizer.stopSpeaking(at: .immediate) }
            pending?.resume(returning: ok)
        }
    }
}
