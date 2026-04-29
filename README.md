# free-SlapMac

一個免費的 SlapMac clone — 拍打你的 MacBook，它就會慘叫。自由上傳你自己的音效包。

## 功能

- **選單列常駐**，不佔 Dock 圖示
- **拍打偵測**：使用麥克風偵測瞬間峰值（M1+ macOS 沒公開加速度計 API，這是可行且穩定的方案）
- **力道感應**：拍打越大聲播放越大聲（可設定最小音量底限）
- **隨機慘叫**：從你的音效庫中隨機抽一個播放，避免連續重複
- **勾選啟用**：音效清單可用勾選框控制哪些要加入隨機池，不想刪掉但暫時不用就取消勾選
- **自由上傳**：支援 mp3 / wav / m4a / aiff；面板上傳或直接拖放
- **靈敏度/音量**可即時調整
- **設定持久化**：音效檔與設定儲存在 `~/Library/Application Support/SlapMac/`

## 執行

需要 macOS 13+，以及 Xcode Command Line Tools（`xcode-select --install`）。

```bash
./build.sh
open ./SlapMac.app
```

或直接下載 [Releases](../../releases) 裡打包好的 `SlapMac-v*.zip`（arm64）。

首次啟動時 macOS 會詢問麥克風權限（Info.plist 已包含說明文字），允許後即可使用。沒上傳任何音效時，設定視窗會自動開啟讓你上傳。

## 使用

1. 點選單列的 🖐 圖示打開面板
2. 「上傳音效…」挑選一或多個音效檔案（或直接拖放到設定視窗）
3. 試拍打你的 MacBook 殼（輕拍也行）
4. 面板上的切換可隨時啟用/停用偵測
5. 右鍵選單列圖示：快速切換偵測、開設定、離開

## 參數調校

- **靈敏度**：往「兔子」方向越敏感；誤觸變多時往「烏龜」調
- **主音量**：所有播放的基礎音量
- **最小音量（設定視窗內）**：輕碰時仍會以這個音量播放，避免完全聽不見

## 檔案位置

```
~/Library/Application Support/SlapMac/
  ├── pack.json      # 音效索引
  └── Sounds/        # 實際音效檔
```

可以在 popover 按「顯示音效資料夾」或在設定視窗按「顯示於 Finder」直接打開。

## 技術架構

- SwiftUI + AppKit（`NSStatusItem` + `NSPopover`）
- AVAudioEngine 的 input tap 取得音訊緩衝
- 對每個 buffer 計算 peak amplitude → 閾值判斷 + refractory 不反應期（180 ms，避免一次拍打連發）
- AVAudioPlayer 播放音效，音量 = `minFloor + (1 - minFloor) * intensity`
- 配置存 `UserDefaults`，音效檔與索引存 Application Support

## 為何不用加速度計？

macOS 上 `CoreMotion` 只在 iOS/watchOS 有用；Intel Mac 的 SMS 在 Apple Silicon 已停用；M1+ 雖有加速度計但無公開 API。麥克風偵測在實務上對「拍打外殼」這個動作非常準（每一次敲擊都會在機殼內產生強烈的瞬間聲響），而且完全不需私有 API。

## 隱私

麥克風資料只在記憶體即時處理（只算每個 buffer 的峰值），不錄音、不寫檔、不上傳。
