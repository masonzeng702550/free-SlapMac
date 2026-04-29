import Foundation
import AVFoundation
import AppKit

struct SoundEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var displayName: String
    var fileName: String
    var isEnabled: Bool = true

    init(id: UUID, displayName: String, fileName: String, isEnabled: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.fileName = try c.decode(String.self, forKey: .fileName)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

enum TrimError: Error {
    case exporterUnavailable
    case exportFailed(String)
    case entryNotFound
}

@MainActor
final class SoundPack: ObservableObject {
    static let maxDuration: Double = 5.0
    static let minDuration: Double = 0.1

    @Published private(set) var entries: [SoundEntry] = []
    @Published var masterVolume: Float = 1.0 {
        didSet { UserDefaults.standard.set(masterVolume, forKey: "masterVolume") }
    }
    @Published var minVolumeFloor: Float = 0.25 {
        didSet { UserDefaults.standard.set(minVolumeFloor, forKey: "minVolumeFloor") }
    }

    private let soundsDir: URL
    private let indexURL: URL
    private var lastIndex: Int = -1
    private var activePlayers: [AVAudioPlayer] = []

    init() {
        let fm = FileManager.default
        let base = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("SlapMac", isDirectory: true)
        let sounds = root.appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: sounds, withIntermediateDirectories: true)
        self.soundsDir = sounds
        self.indexURL = root.appendingPathComponent("pack.json")

        if let v = UserDefaults.standard.object(forKey: "masterVolume") as? Float {
            self.masterVolume = v
        }
        if let v = UserDefaults.standard.object(forKey: "minVolumeFloor") as? Float {
            self.minVolumeFloor = v
        }
        loadIndex()
    }

    func url(for entry: SoundEntry) -> URL {
        soundsDir.appendingPathComponent(entry.fileName)
    }

    func reveal() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: soundsDir.path)
    }

    func importPanel() {
        let panel = NSOpenPanel()
        panel.title = "選擇要加入音效包的聲音（可多選）"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mp3, .wav, .mpeg4Audio, .aiff, .data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(from: url)
        }
    }

    func add(from source: URL) {
        let fm = FileManager.default
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
        let id = UUID()
        let dest = soundsDir.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            try fm.copyItem(at: source, to: dest)
            let entry = SoundEntry(
                id: id,
                displayName: source.deletingPathExtension().lastPathComponent,
                fileName: dest.lastPathComponent
            )
            entries.append(entry)
            saveIndex()
        } catch {
            NSLog("copy failed: \(error)")
        }
    }

    /// 讀取音檔時間長度（秒）。
    func loadDuration(of entry: SoundEntry) async -> Double {
        let asset = AVURLAsset(url: url(for: entry))
        do {
            let d = try await asset.load(.duration)
            return max(0, d.seconds)
        } catch {
            NSLog("load duration failed: \(error)")
            return 0
        }
    }

    /// 將某個項目裁切成 [start, start+length] 的片段，length 會被限制在 maxDuration 內；
    /// 成功後覆蓋原檔（輸出為 m4a）。
    func trim(entry: SoundEntry, start: Double, length: Double) async throws -> SoundEntry {
        let clampedLen = min(Self.maxDuration, max(Self.minDuration, length))
        let srcURL = url(for: entry)
        let asset = AVURLAsset(url: srcURL)
        let totalSec = (try? await asset.load(.duration).seconds) ?? 0
        let clampedStart = min(max(0, start), max(0, totalSec - Self.minDuration))
        let end = min(totalSec, clampedStart + clampedLen)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TrimError.exporterUnavailable
        }
        let scale: CMTimeScale = 600
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: clampedStart, preferredTimescale: scale),
            end:   CMTime(seconds: end,          preferredTimescale: scale)
        )
        exporter.outputFileType = .m4a
        let destURL = soundsDir.appendingPathComponent("\(UUID().uuidString).m4a")
        exporter.outputURL = destURL

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed: cont.resume()
                default: cont.resume(throwing: TrimError.exportFailed(
                    exporter.error?.localizedDescription ?? "status=\(exporter.status.rawValue)"))
                }
            }
        }

        try? FileManager.default.removeItem(at: srcURL)
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else {
            try? FileManager.default.removeItem(at: destURL)
            throw TrimError.entryNotFound
        }
        entries[i].fileName = destURL.lastPathComponent
        saveIndex()
        return entries[i]
    }

    func remove(_ entry: SoundEntry) {
        try? FileManager.default.removeItem(at: url(for: entry))
        entries.removeAll { $0.id == entry.id }
        saveIndex()
    }

    func removeAll() {
        for e in entries {
            try? FileManager.default.removeItem(at: url(for: e))
        }
        entries.removeAll()
        saveIndex()
    }

    func rename(_ entry: SoundEntry, to name: String) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].displayName = name.isEmpty ? entries[i].displayName : name
        saveIndex()
    }

    func setEnabled(_ entry: SoundEntry, to enabled: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].isEnabled = enabled
        saveIndex()
    }

    func enableAll() {
        for i in entries.indices { entries[i].isEnabled = true }
        saveIndex()
    }

    func disableAll() {
        for i in entries.indices { entries[i].isEnabled = false }
        saveIndex()
    }

    var enabledCount: Int { entries.lazy.filter { $0.isEnabled }.count }

    /// 根據拍打力道（0..1）隨機選一個音效播放。同時間只播一個，新觸發會覆蓋舊的。
    /// 只會從已勾選啟用的音效中挑選。
    func playRandom(intensity: Float) {
        let pool = entries.enumerated().filter { $0.element.isEnabled }
        guard !pool.isEmpty else { return }
        // 單音模式：先停掉所有在播的
        activePlayers.forEach { $0.stop() }
        activePlayers.removeAll()
        let idx = randomIndex(pool: pool.map { $0.offset })
        let entry = entries[idx]
        let clipVol = minVolumeFloor + (1 - minVolumeFloor) * max(0, min(1, intensity))
        let vol = clipVol * masterVolume
        do {
            let player = try AVAudioPlayer(contentsOf: url(for: entry))
            player.volume = vol
            player.prepareToPlay()
            player.play()
            activePlayers.append(player)
            // 清理已播完的 player。
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((player.duration + 0.5) * 1_000_000_000))
                await MainActor.run {
                    self?.activePlayers.removeAll { !$0.isPlaying }
                }
            }
        } catch {
            NSLog("play failed: \(error)")
        }
    }

    func stopAll() {
        activePlayers.forEach { $0.stop() }
        activePlayers.removeAll()
    }

    /// 從指定 index 池中隨機挑一個，並盡量避免連續重複。
    private func randomIndex(pool: [Int]) -> Int {
        if pool.count == 1 { return pool[0] }
        var i = pool.randomElement()!
        if i == lastIndex, let alt = pool.first(where: { $0 != lastIndex }) {
            i = alt
        }
        lastIndex = i
        return i
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SoundEntry].self, from: data) else {
            return
        }
        // 只保留實體檔案仍在的項目。
        entries = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexURL)
        }
    }
}
