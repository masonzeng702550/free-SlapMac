import Foundation
import IOKit
import IOKit.hid

// slap_helper：純 CLI 子程序，讀 HID sensor，每個 report 印一行 Δ 到 stdout。
// 主 app 用 Process 啟動它、pipe stdout。因為沒呼叫 NSApplication，
// macOS TCC 不會把它當 "GUI app" 擋 HID 事件。

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(mgr, nil)
IOHIDManagerOpen(mgr, 0)
guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
    FileHandle.standardError.write("ERR no HID manager\n".data(using: .utf8)!)
    exit(2)
}
var target: IOHIDDevice?
for d in devs {
    let t = (IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String) ?? ""
    let p = (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
    let u = (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
    if t == "SPU" && p == 0xff00 && u == 0x04 { target = d; break }
}
guard let dev = target else {
    FileHandle.standardError.write("ERR no motion sensor device\n".data(using: .utf8)!)
    exit(3)
}
let openR = IOHIDDeviceOpen(dev, 0)
if openR != kIOReturnSuccess {
    FileHandle.standardError.write(
        "ERR open kr=0x\(String(openR, radix: 16))\n".data(using: .utf8)!)
    exit(4)
}

let axisOffsets = [20, 24, 28, 32, 36]
final class State { var prev: [Int]? = nil; var warm = 0 }
let state = State()
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)

let cb: IOHIDReportCallback = { _, _, _, _, rid, report, reportLen in
    let len = Int(reportLen)
    if rid != 0 || len < 40 { return }
    var cur = [Int]()
    cur.reserveCapacity(axisOffsets.count)
    for o in axisOffsets {
        let u = Int(report[o]) | (Int(report[o + 1]) << 8)
        cur.append(u >= 0x8000 ? u - 0x10000 : u)
    }
    defer { state.prev = cur }
    guard let prev = state.prev else { return }
    state.warm += 1
    if state.warm < 3 { return }
    var total = 0
    for i in 0..<cur.count { total += abs(cur[i] - prev[i]) }
    // 輸出格式：一行 "D <delta>\n"
    let line = "D \(total)\n"
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
}
IOHIDDeviceRegisterInputReportCallback(dev, buf, 256, cb, nil)
IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(),
                               CFRunLoopMode.defaultMode.rawValue)

// 讓 stdout 不 buffer，否則 parent 看不到
setbuf(stdout, nil)
FileHandle.standardError.write("READY\n".data(using: .utf8)!)

CFRunLoopRun()  // 無限跑
