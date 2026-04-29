import Foundation

@MainActor
final class DetectionConfig: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable, Codable {
        case microphone = "麥克風"
        case accelerometer = "加速度計"
        case both = "兩者"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .microphone {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "detectionMode")
            onChange?(mode)
        }
    }

    /// AppDelegate 註冊以回應模式切換。
    var onChange: ((Mode) -> Void)?

    init() {
        if let s = UserDefaults.standard.string(forKey: "detectionMode"),
           let m = Mode(rawValue: s) {
            self.mode = m
        }
    }
}
