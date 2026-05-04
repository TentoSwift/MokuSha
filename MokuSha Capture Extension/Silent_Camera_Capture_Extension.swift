//
//  Silent_Camera_Capture_Extension.swift
//  Silent Camera Capture Extension
//
//  Created by Tento Ishino on 2026/04/28.
//  Copyright © 2026 Tento Ishino. All rights reserved.
//


import ExtensionKit
import Foundation
import LockedCameraCapture
import SwiftUI

@main
struct Silent_Camera_Capture_Extension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            Silent_Camera_Capture_ExtensionViewFinder(session: session)
        }
    }
}
