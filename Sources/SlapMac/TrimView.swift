import SwiftUI
import AVFoundation

struct TrimView: View {
    let entryID: UUID
    @EnvironmentObject var pack: SoundPack
    @Binding var isPresented: Bool

    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var length: Double = SoundPack.maxDuration
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var preview: AVAudioPlayer?
    @State private var previewStopTask: Task<Void, Never>?

    private var entry: SoundEntry? {
        pack.entries.first(where: { $0.id == entryID })
    }

    private var maxStart: Double {
        max(0, duration - SoundPack.minDuration)
    }
    private var maxLengthNow: Double {
        min(SoundPack.maxDuration, max(SoundPack.minDuration, duration - start))
    }
    private var end: Double { start + length }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "scissors").foregroundColor(.accentColor)
                Text("剪輯音效（上限 5 秒）").font(.title3).bold()
                Spacer()
            }

            if let entry {
                Text(entry.displayName).foregroundColor(.secondary)
            }

            if isLoading {
                ProgressView("讀取音檔…").frame(maxWidth: .infinity)
            } else if let err = errorText {
                Text(err).foregroundColor(.red)
            } else {
                rangeVisual
                controls
                HStack {
                    Button {
                        playPreview()
                    } label: {
                        Label("試聽選取範圍", systemImage: "play.circle")
                    }
                    .disabled(isSaving)
                    Spacer()
                    Text(String(format: "總長 %.2fs｜選取 %.2fs – %.2fs（%.2fs）",
                                duration, start, end, length))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    stopPreview()
                    isPresented = false
                }
                .disabled(isSaving)
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text("儲存裁切") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || isSaving || errorText != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await load() }
        .onDisappear { stopPreview() }
    }

    private var rangeVisual: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let s = duration > 0 ? CGFloat(start / duration) * w : 0
            let lw = duration > 0 ? CGFloat(length / duration) * w : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: max(4, lw))
                    .offset(x: s)
            }
        }
        .frame(height: 28)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("起始時間").frame(width: 80, alignment: .leading)
                    Slider(value: Binding(
                        get: { start },
                        set: { newValue in
                            start = min(newValue, maxStart)
                            // 若新的起始讓 length 超過剩餘，裁短 length。
                            length = min(length, maxLengthNow)
                        }
                    ), in: 0...max(0.001, maxStart))
                    Text(String(format: "%.2fs", start))
                        .frame(width: 54, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("長度").frame(width: 80, alignment: .leading)
                    Slider(value: Binding(
                        get: { length },
                        set: { newValue in
                            length = min(SoundPack.maxDuration,
                                         max(SoundPack.minDuration, newValue))
                            length = min(length, maxLengthNow)
                        }
                    ), in: SoundPack.minDuration...max(SoundPack.minDuration + 0.001,
                                                       maxLengthNow))
                    Text(String(format: "%.2fs", length))
                        .frame(width: 54, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
    }

    private func load() async {
        guard let entry else {
            errorText = "找不到項目"
            isLoading = false
            return
        }
        let d = await pack.loadDuration(of: entry)
        duration = d
        if d <= 0 {
            errorText = "無法讀取音檔長度"
            isLoading = false
            return
        }
        start = 0
        length = min(SoundPack.maxDuration, max(SoundPack.minDuration, d))
        isLoading = false
    }

    private func playPreview() {
        stopPreview()
        guard let entry else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: pack.url(for: entry))
            p.currentTime = start
            p.volume = pack.masterVolume
            p.prepareToPlay()
            p.play()
            preview = p
            let ms = UInt64(length * 1_000_000_000)
            previewStopTask = Task { [weak p] in
                try? await Task.sleep(nanoseconds: ms)
                await MainActor.run { p?.stop() }
            }
        } catch {
            errorText = "試聽失敗：\(error.localizedDescription)"
        }
    }

    private func stopPreview() {
        previewStopTask?.cancel()
        previewStopTask = nil
        preview?.stop()
        preview = nil
    }

    private func save() async {
        guard let entry else { return }
        stopPreview()
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await pack.trim(entry: entry, start: start, length: length)
            isPresented = false
        } catch {
            errorText = "裁切失敗：\(error.localizedDescription)"
        }
    }
}
