//
//  ContentView.swift
//  登录门 + 三页签 + 顶部提示条 + 前台定时刷新
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase

    private let tick = Timer.publish(every: AppConfig.refreshInterval,
                                     on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if state.isLoggedIn {
                main
            } else {
                LoginView()
            }
        }
        .tint(Palette.accent)
        .overlay(alignment: .top) { toastLayer }
        .task {
            if state.isLoggedIn {
                await state.refresh(silent: true)
            } else if !AppConfig.defaultPassword.isEmpty, state.autoLoginAllowed {
                await state.login(user: AppConfig.defaultUser,
                                  pass: AppConfig.defaultPassword)
            }
        }
        .onReceive(tick) { _ in
            guard scenePhase == .active, state.isLoggedIn else { return }
            Task { await state.refresh(silent: true) }
        }
    }

    private var main: some View {
        TabView {
            DevicesView()
                .tabItem { Label("设备", systemImage: "power.circle.fill") }
            LogsView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
                .badge(state.logs.count)
            SettingsView()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let t = state.toast {
            HStack(spacing: 10) {
                Image(systemName: t.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.ok ? Palette.good : Palette.bad)
                Text(t.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
