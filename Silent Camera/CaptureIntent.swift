import AppIntents

extension Notification.Name {
    static let cameraControlDidActivate = Notification.Name("cameraControlDidActivate")
}

struct CaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "Silent Camera"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        // メインアプリが動作中の場合は通知で伝える
        // Extension（ロック画面）から実行の場合は Extension の UI が処理する
        NotificationCenter.default.post(name: .cameraControlDidActivate, object: nil)
        return .result()
    }
}
