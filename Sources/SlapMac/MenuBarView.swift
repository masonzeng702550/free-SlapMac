import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct MenuBarView: View {
    @EnvironmentObject var detector: SlapDetector
    @EnvironmentObject var hidDetector: HIDMotionDetector
    @EnvironmentObject var pack: SoundPack
    @EnvironmentObject var config: DetectionConfig
    @Binding var showSettings: Bool

    private var anyRunning: Bool { detector.isRunning || hidDetector.isRunning }
    private var isInBand: Bool {
        hidDetector.latestDelta >= hidDetector.minThreshold
            && hidDetector.latestDelta <= hidDetector.maxThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            sliderSection
            librarySection
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("離開 SlapMac", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("free-SlapMac")
                    .font(.headline)
                Spacer()
            }
            Picker("模式", selection: $config.mode) {
                ForEach(DetectionConfig.Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let err = detector.lastError, config.mode != .accelerometer {
                Text("麥克風：\(err)").font(.caption).foregroundColor(.red)
            }
            if let err = hidDetector.lastError, config.mode != .microphone {
                Text("加速度計：\(err)").font(.caption).foregroundColor(.red)
            }
            Text(anyRunning
                 ? (pack.entries.isEmpty
                    ? "尚未上傳任何音效"
                    : (pack.enabledCount == 0
                       ? "已上傳但全部停用，請勾選要使用的音效"
                       : "監聽中・拍一下試試"))
                 : "目前停用（點上方模式啟動）")
                .font(.caption).foregroundColor(.secondary)
            Divider()
        }
    }

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if config.mode != .accelerometer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("麥克風靈敏度").font(.caption).foregroundColor(.secondary)
                    HStack {
                        Image(systemName: "tortoise.fill").foregroundColor(.secondary)
                        Slider(value: $detector.sensitivity, in: 0...1)
                        Image(systemName: "hare.fill").foregroundColor(.secondary)
                    }
                    LevelMeter(level: detector.latestLevel)
                        .frame(height: 6)
                }
            }
            if config.mode != .microphone {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("有效範圍").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "Δ=%.0f　範圍 %.0f–%.0f",
                                   hidDetector.latestDelta,
                                   hidDetector.minThreshold,
                                   hidDetector.maxThreshold))
                            .font(.caption).monospacedDigit()
                            .foregroundColor(isInBand ? .accentColor : .secondary)
                    }
                    LevelMeter(level: hidDetector.latestLevel)
                        .frame(height: 6)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("主音量").font(.caption).foregroundColor(.secondary)
                HStack {
                    Image(systemName: "speaker.fill").foregroundColor(.secondary)
                    Slider(value: $pack.masterVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.secondary)
                }
            }
            Divider()
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("音效庫").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("啟用 \(pack.enabledCount) / \(pack.entries.count)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Button { pack.importPanel() } label: {
                Label("上傳音效…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                showSettings = true
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("管理音效庫…", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                pack.playRandom(intensity: 0.9)
            } label: {
                Label("測試播放（隨機）", systemImage: "play.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(pack.enabledCount == 0)
        }
    }
}

private struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [.green, .yellow, .red],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, level))))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var pack: SoundPack
    @EnvironmentObject var detector: SlapDetector
    @EnvironmentObject var hidDetector: HIDMotionDetector
    @EnvironmentObject var config: DetectionConfig
    @State private var renaming: SoundEntry?

    private var isInBand: Bool {
        hidDetector.latestDelta >= hidDetector.minThreshold
            && hidDetector.latestDelta <= hidDetector.maxThreshold
    }
    @State private var renameText: String = ""
    @State private var isTargeted = false
    @State private var trimming: SoundEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                Text("SlapMac 音效庫").font(.title2).bold()
                Spacer()
                Button {
                    pack.importPanel()
                } label: {
                    Label("上傳音效", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }

            GroupBox("偵測模式") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("模式", selection: $config.mode) {
                        ForEach(DetectionConfig.Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(descriptionFor(config.mode))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    // 加速度計狀態永遠顯示，方便診斷
                    HStack(spacing: 10) {
                        Circle()
                            .fill(hidDetector.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text("加速度計：\(hidDetector.isRunning ? "運作中" : "停用")")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "Δ=%.0f　峰值=%.0f",
                                    hidDetector.latestDelta, hidDetector.latestPeak))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(
                                hidDetector.isRunning
                                ? (isInBand ? .accentColor : .primary)
                                : .secondary
                            )
                    }
                    LevelMeter(level: hidDetector.latestLevel).frame(height: 10)

                    HStack {
                        Text("下限").frame(width: 60, alignment: .leading)
                        Slider(value: $hidDetector.minThreshold,
                               in: 0...max(hidDetector.maxThreshold - 1, 1))
                        Text(String(format: "%.0f", hidDetector.minThreshold))
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("上限").frame(width: 60, alignment: .leading)
                        Slider(value: $hidDetector.maxThreshold,
                               in: max(hidDetector.minThreshold + 1, 2)...500)
                        Text(String(format: "%.0f", hidDetector.maxThreshold))
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                    }

                    if let err = hidDetector.lastError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }

                    Text("只有 Δ 落在「下限 ≤ Δ ≤ 上限」時才觸發播放。低於下限視為 baseline 雜訊，高於上限視為誤觸/搬動。預設 15–100。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }

            GroupBox("拍打設定") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("麥克風靈敏度").frame(width: 100, alignment: .leading)
                        Slider(value: $detector.sensitivity, in: 0...1)
                        Text(String(format: "%.0f%%", detector.sensitivity * 100))
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("最小音量").frame(width: 100, alignment: .leading)
                        Slider(value: $pack.minVolumeFloor, in: 0...1)
                        Text(String(format: "%.0f%%", pack.minVolumeFloor * 100))
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .help("輕碰時仍會播放這個音量，避免聽不見")
                    HStack {
                        Text("主音量").frame(width: 100, alignment: .leading)
                        Slider(value: $pack.masterVolume, in: 0...1)
                        Text(String(format: "%.0f%%", pack.masterVolume * 100))
                            .frame(width: 44, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
                .padding(8)
            }

            GroupBox("音效清單（啟用 \(pack.enabledCount) / 共 \(pack.entries.count)）") {
                VStack(alignment: .leading, spacing: 6) {
                    if pack.entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("拖放音效檔到此處，或按右上方「上傳音效」")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(pack.entries) { entry in
                                    row(for: entry)
                                }
                            }
                        }
                        .frame(minHeight: 200, maxHeight: 320)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isTargeted ? Color.accentColor : Color.clear,
                                lineWidth: 2)
                )
                .onDrop(of: [.fileURL, .audio], isTargeted: $isTargeted) { providers in
                    var handled = false
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            guard let url else { return }
                            DispatchQueue.main.async { pack.add(from: url) }
                        }
                        handled = true
                    }
                    return handled
                }
            }

            HStack {
                Button {
                    pack.reveal()
                } label: {
                    Label("顯示於 Finder", systemImage: "folder")
                }
                Button {
                    pack.enableAll()
                } label: {
                    Label("全部啟用", systemImage: "checkmark.square")
                }
                .disabled(pack.entries.isEmpty)
                Button {
                    pack.disableAll()
                } label: {
                    Label("全部停用", systemImage: "square")
                }
                .disabled(pack.entries.isEmpty)
                Button(role: .destructive) {
                    pack.removeAll()
                } label: {
                    Label("清空全部", systemImage: "trash")
                }
                .disabled(pack.entries.isEmpty)
                Spacer()
                Button {
                    pack.playRandom(intensity: 0.9)
                } label: {
                    Label("測試播放", systemImage: "play.circle.fill")
                }
                .disabled(pack.enabledCount == 0)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .sheet(item: $renaming) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text("重新命名").font(.headline)
                TextField("名稱", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                HStack {
                    Spacer()
                    Button("取消") { renaming = nil }
                    Button("儲存") {
                        pack.rename(entry, to: renameText)
                        renaming = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .sheet(item: $trimming) { entry in
            TrimView(
                entryID: entry.id,
                isPresented: Binding(
                    get: { trimming != nil },
                    set: { if !$0 { trimming = nil } }
                )
            )
            .environmentObject(pack)
        }
    }

    private func descriptionFor(_ mode: DetectionConfig.Mode) -> String {
        switch mode {
        case .microphone:
            return "使用內建麥克風偵測拍打聲的瞬間峰值。反應快、對拍打靈敏；會受環境噪音影響。"
        case .accelerometer:
            return "讀取 Apple Silicon 內建動作感測器（HID SPU）的姿態資料，以欄位變化總和判定動作。採樣率 ~5Hz，對緩慢搖晃較敏感、對瞬間拍打可能漏報。"
        case .both:
            return "兩個引擎並用：任一觸發都會發聲。最靈敏但可能稍多誤觸。"
        }
    }

    private func row(for entry: SoundEntry) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { pack.setEnabled(entry, to: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(entry.isEnabled ? "取消勾選後隨機播放不會選到此音效" : "勾選以加入隨機播放池")
            Image(systemName: "waveform")
                .foregroundColor(entry.isEnabled ? .accentColor : .secondary)
            Text(entry.displayName)
                .lineLimit(1)
                .foregroundColor(entry.isEnabled ? .primary : .secondary)
            Spacer()
            Button {
                _ = try? AVAudioPlayerBox.play(url: pack.url(for: entry),
                                               volume: pack.masterVolume)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("試聽")
            Button {
                trimming = entry
            } label: {
                Image(systemName: "scissors")
            }
            .buttonStyle(.borderless)
            .help("剪輯（上限 5 秒）")
            Button {
                renameText = entry.displayName
                renaming = entry
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("重新命名")
            Button {
                pack.remove(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("刪除")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }
}

enum AVAudioPlayerBox {
    @MainActor static var current: AVAudioPlayer?
    @MainActor static func play(url: URL, volume: Float) throws {
        let p = try AVAudioPlayer(contentsOf: url)
        p.volume = volume
        p.prepareToPlay()
        p.play()
        current = p
    }
}
