import AppKit
import CoreGraphics
import CoreText
import Foundation

// 生成 SlapMac 的 app icon：橘色圓角背景 + 白色舉起的手。
// 用法：swift scripts/make_icon.swift <輸出 iconset 目錄>

func renderIcon(size: Int) -> Data {
    let pxSize = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("cannot create CGContext")
    }

    // 圓角背景
    let r: CGFloat = pxSize * 0.2237 // macOS Big Sur 圖示半徑
    let bgRect = CGRect(x: 0, y: 0, width: pxSize, height: pxSize)
    let path = CGPath(roundedRect: bgRect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // 橘色漸層
    let colors = [
        CGColor(red: 1.00, green: 0.58, blue: 0.22, alpha: 1.0), // 左上亮橘
        CGColor(red: 0.95, green: 0.36, blue: 0.08, alpha: 1.0)  // 右下深橘
    ] as CFArray
    let locs: [CGFloat] = [0.0, 1.0]
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: 0, y: pxSize),
            end: CGPoint(x: pxSize, y: 0),
            options: []
        )
    }

    // 輕微 inner shadow for 質感（畫個暗邊）
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.08))
    ctx.setLineWidth(pxSize * 0.01)
    ctx.addPath(path)
    ctx.strokePath()

    // 畫一隻白色的手（風格化、不用 SF Symbols 以避免授權與尺寸問題）
    drawHand(in: ctx, canvas: pxSize)

    guard let cgImage = ctx.makeImage() else {
        fatalError("cannot make image")
    }

    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pxSize, height: pxSize)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode png")
    }
    return data
}

func drawHand(in ctx: CGContext, canvas s: CGFloat) {
    ctx.saveGState()

    // 縮放到 1000 單位座標讓手繪路徑好寫，再映射回 s
    let scale = s / 1000.0
    ctx.scaleBy(x: scale, y: scale)

    // 手掌與五指的路徑（座標系原點左下）
    // 手掌
    let palm = CGMutablePath()
    palm.move(to: CGPoint(x: 300, y: 200))
    palm.addCurve(to: CGPoint(x: 700, y: 200),
                  control1: CGPoint(x: 360, y: 140),
                  control2: CGPoint(x: 640, y: 140))
    palm.addLine(to: CGPoint(x: 720, y: 520))
    palm.addCurve(to: CGPoint(x: 280, y: 520),
                  control1: CGPoint(x: 660, y: 580),
                  control2: CGPoint(x: 340, y: 580))
    palm.closeSubpath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(palm)
    ctx.fillPath()

    // 五指：各自畫圓角膠囊
    struct Finger { var x: CGFloat; var top: CGFloat; var w: CGFloat }
    let fingers: [Finger] = [
        Finger(x: 310, top: 770, w: 80),  // 食指
        Finger(x: 420, top: 830, w: 86),  // 中指
        Finger(x: 530, top: 810, w: 84),  // 無名指
        Finger(x: 635, top: 740, w: 78),  // 小指
    ]
    for f in fingers {
        let rect = CGRect(x: f.x, y: 470, width: f.w, height: f.top - 470)
        let rp = CGPath(roundedRect: rect, cornerWidth: f.w/2, cornerHeight: f.w/2, transform: nil)
        ctx.addPath(rp)
        ctx.fillPath()
    }
    // 大拇指：斜向
    ctx.saveGState()
    ctx.translateBy(x: 250, y: 440)
    ctx.rotate(by: 0.55) // rad
    let thumb = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 80, height: 260),
                       cornerWidth: 40, cornerHeight: 40, transform: nil)
    ctx.addPath(thumb)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()
}

// === Main ===
guard CommandLine.arguments.count >= 2 else {
    print("usage: swift make_icon.swift <iconset_dir>")
    exit(2)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// macOS iconset 標準尺寸
let specs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    let data = renderIcon(size: spec.size)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(spec.name)
    try! data.write(to: url)
    print("wrote \(url.path) (\(data.count) bytes)")
}
