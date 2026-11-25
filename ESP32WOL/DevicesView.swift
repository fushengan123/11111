//
//  DevicesView.swift
//  首屏 UI：状态环 → 主唤醒按钮 → 最近一次 → 设备卡列表
//

import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusHero()
                    WakeAllCard()
                    RecentStrip()
                    DeviceSection()
                    HintCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 32)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("远程开机")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.tap()
                        Task { await state.refresh() }
                    } label: {
                        if state.isBusy("refresh") {
                            ProgressView().tint(Palette.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(state.isBusy("refresh"))
                }
            }
        }
    }
}

// MARK: - 状态环

struct SignalRing: View {
    let quality: Double
    let online: Bool

    private var clamped: Double { min(1.0, max(0.03, quality)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.stroke, lineWidth: 5)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [
                            Palette.accent,
                            Color(red: 0.20, green: 0.62, blue: 0.95),
                            Palette.accent
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.45), value: clamped)
            Image(systemName: online ? "wifi" : "wifi.slash")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(online ? Palette.accent : Palette.sub)
        }
        .frame(width: 64, height: 64)
    }
}

struct StatusHero: View {
    @EnvironmentObject private var state: AppState

    private var ipText: String {
        let ip = state.status?.ip ?? ""
        return ip.isEmpty ? "—" : ip
    }

    private var detail: String {
        var parts: [String] = []
        if let sta = state.status?.sta, !sta.isEmpty { parts.append(sta) }
        if let t = state.status?.time, !t.isEmpty { parts.append(t) }
        if let fw = state.status?.fw, !fw.isEmpty { parts.append(fw) }
        if parts.isEmpty { parts.append(AppConfig.serverLabel) }
        return parts.joined(separator: "  ·  ")
    }

    private var dot: Color { state.online ? Palette.good : Palette.bad }

    var body: some View {
        HStack(spacing: 16) {
            SignalRing(quality: state.status?.quality ?? 0, online: state.online)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                        .shadow(color: dot.opacity(0.85), radius: 6)
                    Text(state.online ? "ESP32 在线" : "ESP32 离线")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(dot)
                }

                Text(ipText)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .card()
    }
}

// MARK: - 主唤醒

struct WakeAllCard: View {
    @EnvironmentObject private var state: AppState
    @State private var pulse = false

    private var busy: Bool { state.isBusy("all") }

    private var subtitle: String {
        if state.deviceCount > 0 {
            return "\(state.deviceCount) 台设备 · 每台 \(state.rounds) 轮广播"
        }
        return state.online ? "还没保存设备，先去固件网页添加" : "先连上 ESP32"
    }

    var body: some View {
        Button {
            Haptics.tap()
            Task { await state.wakeAll() }
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: 48, height: 48)
                    if busy {
                        ProgressView().tint(Palette.ink)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 22, weight: .heavy))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("全部唤醒")
                        .font(.title3.weight(.heavy))
                        .tracking(0.5)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .opacity(0.75)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .opacity(0.4)
            }
            .foregroundStyle(Palette.ink)
            .padding(17)
            .background(
                LinearGradient(
                    colors: [Palette.accent, Color(red: 0.14, green: 0.58, blue: 0.93)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Palette.accent.opacity(0.20), radius: 20, y: 10)
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .overlay(pulseRing)
        .onChange(of: busy) { value in
            if value {
                pulse = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }

    private var pulseRing: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Palette.accent.opacity(0.55), lineWidth: 2)
            .scaleEffect(pulse ? 1.045 : 1.0)
            .opacity(busy ? (pulse ? 0.0 : 0.9) : 0.0)
            .allowsHitTesting(false)
    }
}

/// 按压回弹
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 最近一次

struct RecentStrip: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let log = state.latestLog {
            HStack(spacing: 9) {
                Image(systemName: log.succeeded ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(log.succeeded ? Palette.good : Palette.bad)
                Text(log.t)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.sub)
                Text(log.dev)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(log.pk) 包")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.sub)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
        }
    }
}

// MARK: - 设备清单

struct DeviceSection: View {
    @EnvironmentObject private var state: AppState
    @State private var stopTarget: ESPDevice?
    @State private var showStop = false

    var body: some View {
        Group {
            bodyContent
        }
        .confirmationDialog("远程关机？", isPresented: $showStop, titleVisibility: .visible) {
            Button("关机", role: .destructive) {
                if let target = stopTarget {
                    Task { await state.shutdown(target) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("「" + (stopTarget?.displayName ?? "") + "」会在 5 秒后关机，未保存的内容可能丢失。")
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        let devices = state.devices
        if devices.isEmpty {
            EmptyDevices()
        } else {
            VStack(spacing: 10) {
                HStack {
                    Text("设备列表")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.sub)
                        .tracking(0.8)
                    Spacer()
                    Text("\(devices.count) / 8")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.sub)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)

                ForEach(devices) { device in
                    DeviceCard(device: device, pc: state.pcState(for: device)) { target in
                        stopTarget = target
                        showStop = true
                    }
                }
            }
        }
    }
}

struct DeviceCard: View {
    @EnvironmentObject private var state: AppState
    let device: ESPDevice
    let pc: PcState?
    var onStop: (ESPDevice) -> Void

    private var busy: Bool { state.isBusy("dev:" + device.mac) }
    private var stopping: Bool { state.isBusy("stop:" + device.mac) }
    private var pcOn: Bool { pc?.isOn ?? false }

    private var pcColor: Color {
        guard let p = pc else { return Palette.sub }
        return p.isOn ? Palette.good : Palette.sub
    }

    private var pcText: String {
        guard let p = pc else { return "未上报" }
        return p.isOn ? "已开机" : "已关机"
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.accent.opacity(busy ? 0.26 : 0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Circle()
                        .fill(pcColor)
                        .frame(width: 5, height: 5)
                    Text(pcText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(pcColor)
                }

                HStack(spacing: 6) {
                    Text(device.mac)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.sub)
                    if !device.ip.isEmpty {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.sub.opacity(0.5))
                        Text(device.ip)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.sub.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                Haptics.tap()
                onStop(device)
            } label: {
                ZStack {
                    if stopping {
                        ProgressView().tint(Palette.bad)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(width: 42, height: 42)
                .background(Palette.bad.opacity(pcOn ? 0.16 : 0.06))
                .foregroundStyle(pcOn ? Palette.bad : Palette.sub.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .disabled(!pcOn || stopping)

            Button {
                Haptics.tap()
                Task { await state.wake(device) }
            } label: {
                ZStack {
                    if busy {
                        ProgressView().tint(Palette.ink)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 48, height: 42)
                .background(
                    LinearGradient(
                        colors: [Palette.accent, Color(red: 0.18, green: 0.70, blue: 0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundStyle(Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
        }
        .padding(14)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.stroke, lineWidth: 1)
        )
    }
}

struct EmptyDevices: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("还没读到设备列表")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
            }
            Text("到「设置」填好地址、用户名、密码，回这里点右上角刷新。设备清单存在 ESP32 闪存里，最多 8 台。")
                .font(.caption)
                .foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Palette.stroke,
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
        )
    }
}

// MARK: - 底部提示

struct HintCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text("魔术包由 ESP32 在局域网里发出")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Palette.sub)

            Text("手机只负责把唤醒指令送到内置服务器，所以人在外面也能点。电脑没醒，通常是 BIOS / 网卡的 WOL 没开，或者用了无线网卡。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}
