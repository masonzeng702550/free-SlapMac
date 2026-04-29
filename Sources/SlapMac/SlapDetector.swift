import Foundation
import AVFoundation

/// 使用內建麥克風偵測「拍打」瞬間。
/// macOS 沒公開 M1+ 的加速度計，實務上拍打 MacBook 會在麥克風上產生強烈的瞬間峰值，
/// 透過偵測 peak amplitude 超過閾值就能判定為一次拍打。
@MainActor
final class SlapDetector: ObservableObject {
    @Published var isRunning = false
    @Published var latestLevel: Float = 0
    @Published var sensitivity: Float = 0.55 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }
    @Published var lastError: String?

    /// 偵測到一次拍打的回呼，intensity 0.0–1.0 表示力道。
    var onSlap: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var lastTrigger = Date.distantPast
    private let refractory: TimeInterval = 0.18
    private let preAttack: TimeInterval = 0.30
    private var recentPeak: Float = 0
    private var recentPeakAt = Date.distantPast

    init() {
        if let s = UserDefaults.standard.object(forKey: "sensitivity") as? Float {
            self.sensitivity = s
        }
    }

    func start() {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let peak = Self.peakAmplitude(buffer: buffer)
            Task { @MainActor in self.handle(peak: peak) }
        }
        do {
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = "無法啟動麥克風：\(error.localizedDescription)"
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        latestLevel = 0
    }

    /// sensitivity 0..1 映射到 peak 閾值；越靈敏閾值越低。
    private var threshold: Float {
        // 靈敏 0 → 0.55；靈敏 1 → 0.08
        return 0.55 - (sensitivity * 0.47)
    }

    private func handle(peak: Float) {
        // 平滑為 UI 顯示的 level（帶快速衰減）。
        latestLevel = max(peak, latestLevel * 0.85)

        // 追蹤最近 preAttack 秒內的最高峰，用它當作「力道」。
        let now = Date()
        if peak > recentPeak || now.timeIntervalSince(recentPeakAt) > preAttack {
            recentPeak = peak
            recentPeakAt = now
        }

        guard peak > threshold else { return }
        guard now.timeIntervalSince(lastTrigger) > refractory else { return }
        lastTrigger = now

        // 將 peak 映射到 0..1 的 intensity，threshold 是下限、0.9 以上視為最大。
        let span = max(0.001, 0.9 - threshold)
        let intensity = min(1.0, max(0.05, (peak - threshold) / span))
        onSlap?(intensity)
    }

    private static func peakAmplitude(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var peak: Float = 0
        for c in 0..<channels {
            let ptr = data[c]
            for i in 0..<frames {
                let v = abs(ptr[i])
                if v > peak { peak = v }
            }
        }
        return peak
    }
}
