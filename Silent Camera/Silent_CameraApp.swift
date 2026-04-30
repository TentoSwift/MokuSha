//
//  Silent_CameraApp.swift
//  Silent Camera
//
//  Created by Tento Ishino on 2026/04/28.
//  Copyright © 2026 Tento Ishino. All rights reserved.
//


import SwiftUI

@main
struct Silent_CameraApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
