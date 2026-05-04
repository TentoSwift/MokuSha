//
//  MokuShaApp.swift
//  MokuSha
//
//  Created by Tento Ishino on 2026/04/28.
//  Copyright © 2026 Tento Ishino. All rights reserved.
//


import SwiftUI

@main
struct MokuShaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // iOS 26+: Assistive Access 専用のシーンとしてシンプル UI を提供。
        // iOS 25 以下: 上の WindowGroup の RootView 内で
        //   `\.accessibilityAssistiveAccessEnabled` を見て切り替えるため、ここでの宣言は iOS 26 のみ。
        if #available(iOS 26.0, *) {
            AssistiveAccess {
                AssistiveAccessContentView()
            }
        }
    }
}

/// アプリのルート。Assistive Access モードに応じて画面を切り替える。
///   - iOS 26+ で Assistive Access モードに入った時: 上の `AssistiveAccess` シーンが使われるため、ここは通常 UI のみ。
///   - iOS 25 以下で Assistive Access モードに入った時: ここで `AssistiveAccessContentView()` を返す。
///   - 通常モード: オンボーディング → ContentView。
private struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.accessibilityAssistiveAccessEnabled) private var isAssistiveAccessEnabled

    var body: some View {
        if isAssistiveAccessEnabled {
            AssistiveAccessContentView()
        } else if hasCompletedOnboarding {
            ContentView()
        } else {
            OnboardingView {
                withAnimation(.easeInOut(duration: 0.35)) {
                    hasCompletedOnboarding = true
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 1.1, anchor: .center)))
        }
    }
}
