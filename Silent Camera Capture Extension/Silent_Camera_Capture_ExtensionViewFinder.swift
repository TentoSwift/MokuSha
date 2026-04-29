import SwiftUI
import LockedCameraCapture

struct Silent_Camera_Capture_ExtensionViewFinder: View {
    let session: LockedCameraCaptureSession

    var body: some View {
        Color.black.ignoresSafeArea()
            .task {
                let activity = NSUserActivity(activityType: "openCamera")
                try? await session.openApplication(for: activity)
            }
    }
}
