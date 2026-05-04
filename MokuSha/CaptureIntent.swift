import AppIntents
import Foundation

extension Notification.Name {
    nonisolated static let cameraControlDidActivate = Notification.Name("cameraControlDidActivate")
}

struct CaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "MokuSha"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        // メインアプリが動作中の場合は通知で伝える
        // Extension（ロック画面）から実行の場合は Extension の UI が処理する
        NotificationCenter.default.post(name: .cameraControlDidActivate, object: nil)
        return .result()
    }
}
