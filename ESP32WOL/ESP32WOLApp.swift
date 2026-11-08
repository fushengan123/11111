//
//  ESP32WOLApp.swift
//  入口
//

import SwiftUI

@main
struct ESP32WOLApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .onOpenURL { url in
                    let target = url
                    Task { @MainActor in
                        state.handle(url: target)
                    }
                }
        }
    }
}
