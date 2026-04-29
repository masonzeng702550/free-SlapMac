import Foundation
import AppKit

/// 透過 `slap_helper` 子程序讀取內建 HID motion sensor。
///
/// 為什麼要開子 process：`NSApp.run()` 會讓 macOS TCC 把本程序歸類為 "GUI app"，
/// 進而遮蔽 SPU/SEP 上的 HID sensor 事件。把 HID 讀取放到一個沒 NSApp 的 CLI
/// 子 process 就能繞過這個限制；主 app 透過 stdout pipe 讀每個 Δ 值。
@MainActor
final class HIDMotionDetector: ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var latestLevel: Float = 0
    @Published var latestDelta: Float = 0
    @Published var latestPeak: Float = 0
    @Published var minThreshold: Float = 15 {
        didSet { UserDefaults.standard.set(minThreshold, forKey: "hidMin") }
    }
    @Published var maxThreshold: Float = 100 {
        didSet { UserDefaults.standard.set(maxThreshold, forKey: "hidMax") }
    }

    var onSlap: ((Float) -> Void)?

    private var helper: Process?
    private var stdoutReader: FileHandle?
    private var stderrReader: FileHandle?
    private var lineBuffer = Data()
    private var lastFire = Date.distantPast
    private let refractory: TimeInterval = 0.25
    private var pendingAt: Date?
    private var pendingPeak: Float = 0
    private let confirmWindow: TimeInterval = 0.5

    init() {
        if let v = UserDefaults.standard.object(forKey: "hidMin") as? Float {
            minThreshold = v
        }
        if let v = UserDefaults.standard.object(forKey: "hidMax") as? Float {
            maxThreshold = v
        }
    }

    func start() {
        guard !isRunning else { return }
        NSLog("[HID] start() — launching helper")

        // 找 helper binary：和主 binary 同目錄
        guard let mainPath = Bundle.main.executablePath else {
            lastError = "找不到主程式路徑"
            return
        }
        let helperURL = URL(fileURLWithPath: mainPath)
            .deletingLastPathComponent()
            .appendingPathComponent("slap_helper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            lastError = "找不到 slap_helper（路徑：\(helperURL.path)）"
            return
        }

        let p = Process()
        p.executableURL = helperURL
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        // 當子程序結束時清狀態
        p.terminationHandler = { _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.latestLevel = 0
            }
        }

        // stdout → 每行 "D <delta>"
        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.ingest(data: data)
            }
        }

        // stderr → ERR/READY 等訊息
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.handleErrLine(s)
            }
        }

        do {
            try p.run()
            helper = p
            stdoutReader = outPipe.fileHandleForReading
            stderrReader = errPipe.fileHandleForReading
            isRunning = true
            lastError = nil
            NSLog("[HID] helper spawned, pid=\(p.processIdentifier)")
        } catch {
            lastError = "無法啟動 slap_helper：\(error.localizedDescription)"
            NSLog("[HID] spawn failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        stdoutReader?.readabilityHandler = nil
        stderrReader?.readabilityHandler = nil
        helper?.terminate()
        helper = nil
        stdoutReader = nil
        stderrReader = nil
        lineBuffer.removeAll()
        isRunning = false
        latestLevel = 0
    }

    private func ingest(data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let bytesBeforeNewline = lineBuffer.distance(from: lineBuffer.startIndex, to: nl)
            let lineData = lineBuffer.prefix(bytesBeforeNewline)
            lineBuffer.removeFirst(bytesBeforeNewline + 1)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let parts = line.split(separator: " ")
            guard parts.count == 2, parts[0] == "D", let v = Int(parts[1]) else { continue }
            let delta = Float(v)
            latestDelta = delta
            latestPeak = max(latestPeak * 0.85, delta)
            latestLevel = min(1, delta / max(1, maxThreshold))
            let now = Date()

            // (1) Δ > maxThreshold：視為誤擊/搬動，立刻作廢 pending
            if delta > maxThreshold {
                pendingAt = nil
                pendingPeak = 0
                continue
            }

            if let startedAt = pendingAt {
                // 有 pending：看 0.5 秒窗口是否過了
                let elapsed = now.timeIntervalSince(startedAt)
                // 視窗內累計 in-band peak 作為力道
                if delta >= minThreshold {
                    pendingPeak = max(pendingPeak, delta)
                }
                if elapsed >= confirmWindow {
                    // 通過確認 → 觸發
                    lastFire = now
                    let peak = max(pendingPeak, minThreshold)
                    pendingAt = nil
                    pendingPeak = 0
                    let span = max(1, maxThreshold - minThreshold)
                    let intensity = min(1, max(0.3, (peak - minThreshold) / span))
                    onSlap?(intensity)
                }
            } else {
                // 沒 pending：Δ 跨過下限、且不在 refractory 內，就開始 pending
                if delta >= minThreshold,
                   now.timeIntervalSince(lastFire) > refractory {
                    pendingAt = now
                    pendingPeak = delta
                }
            }
        }
    }

    private func handleErrLine(_ s: String) {
        NSLog("[HID helper stderr] \(s.trimmingCharacters(in: .whitespacesAndNewlines))")
        if s.contains("ERR ") {
            lastError = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
