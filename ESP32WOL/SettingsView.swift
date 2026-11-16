//
//  SettingsView.swift
//  双地址（局域网 / 外网）、线路模式、诊断、快捷指令、维护
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmReboot = false
    @State private var copied = false

    private let shortcutURL = "esp32wol://wake"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    firmwareCard
                    shortcutCard
                    maintenanceCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("重启 ESP32？", isPresented: $confirmReboot, titleVisibility: .visible) {
                Button("重启", role: .destructive) {
                    Task { await state.reboot() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("重启大约 10 秒，期间唤醒会失败。配置不会丢失。")
            }
        }
    }

    // MARK: - 连接

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Text("ESP32 地址")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Circle()
                    .fill(state.online ? Palette.good : Palette.bad)
                    .frame(width: 7, height: 7)
                Text(state.online ? "已连接" : "未连接")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.online ? Palette.good : Palette.bad)
            }

            endpointField(
                title: "局域网地址",
                placeholder: "192.168.31.231 或 esp32-wol.local",
                path: .lan,
                text: state.lanHostBinding
            )

            endpointField(
                title: "外网地址",
                placeholder: "f8888.picp.vip:49999 或 100.64.0.5",
                path: .wan,
                text: state.wanHostBinding
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("线路模式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.sub)
                Picker("线路模式", selection: state.routeModeBinding) {
                    ForEach(RouteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    Task { await state.testConnection() }
                } label: {
                    HStack(spacing: 8) {
                        if state.isBusy("refresh") {
                            ProgressView().tint(Palette.ink).scaleEffect(0.85)
                        } else {
                            Image(systemName: "bolt.horizontal.circle.fill")
                        }
                        Text(state.isBusy("refresh") ? "连接中…" : "测试连接")
                            .font(.footnote.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.accent)
                    .foregroundStyle(Palette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(state.isBusy("refresh"))

                Button {
                    Haptics.tap()
                    Task { await state.diagnose() }
                } label: {
                    HStack(spacing: 6) {
                        if state.isBusy("diag") {
                            ProgressView().tint(Palette.text).scaleEffect(0.75)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text("诊断")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Palette.bg)
                    .foregroundStyle(Palette.text)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Palette.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.isBusy("diag"))
            }

            if !state.probes.isEmpty {
                VStack(spacing: 7) {
                    ForEach(state.probes) { probe in
                        probeRow(probe)
                    }
                }
                .padding(11)
                .background(Palette.bg.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(routeHint)
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                FieldRow(
                    title: "用户名",
                    placeholder: "admin",
                    text: state.userBinding,
                    keyboard: .asciiCapable,
                    mono: true
                )
                FieldRow(
                    title: "密码",
                    placeholder: "device password",
                    text: state.passwordBinding,
                    keyboard: .asciiCapable,
                    mono: true,
                    secure: true
                )
            }

            Text("密码保存在系统钥匙串，不在设置里明文留档。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.75))
        }
        .card()
    }

    private var routeHint: String {
        switch state.routeMode {
        case .auto:
            return "自动：先试局域网（2 秒超时），不通立刻切外网；局域网失联后会静默 60 秒不再白等，回家自动恢复。"
        case .lanOnly:
            return "只走局域网。人在外面时唤醒会失败，适合固定在家用。"
        case .wanOnly:
            return "只走外网：隧道域名 / 公网 IP:端口 / Tailscale 的 100.x.x.x。"
        }
    }

    private func endpointField(title: String,
                               placeholder: String,
                               path: NetworkPath,
                               text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: path.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.sub)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.sub)

                if let probe = state.probeResult(path) {
                    Circle()
                        .fill(probe.ok ? Palette.good : Palette.bad)
                        .frame(width: 5, height: 5)
                    Text(probe.ok ? "\(probe.ms) ms" : "不通")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(probe.ok ? Palette.good : Palette.bad)
                }

                Spacer(minLength: 0)

                Button {
                    Haptics.tap()
                    Task { await state.testPath(path) }
                } label: {
                    HStack(spacing: 3) {
                        if state.isBusy("probe:" + path.rawValue) {
                            ProgressView().tint(Palette.accent).scaleEffect(0.6)
                        }
                        Text("测")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.bg)
                    .foregroundStyle(Palette.accent)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            TextField(placeholder, text: text)
                .keyboardType(.URL)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .inputShell()
        }
    }

    private func probeRow(_ probe: PathProbe) -> some View {
        HStack(spacing: 7) {
            Image(systemName: probe.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(probe.ok ? Palette.good : Palette.bad)
            Text(probe.path.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.text)
            Text(probe.host)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Palette.sub)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(probe.ok ? "\(probe.ms) ms" : probe.note)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(probe.ok ? Palette.good : Palette.bad)
                .lineLimit(1)
        }
    }

    // MARK: - 固件配置

    private var firmwareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("固件配置")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("和固件网页那张配置页一一对应，改完直接写进 ESP32 闪存，断点不丢。")
                .font(.caption2)
                .foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                DeviceListView()
            } label: {
                navLabel(title: "设备管理",
                         detail: "\(state.deviceCount) / \(AppConfig.maxDevices) 台",
                         icon: "desktopcomputer")
            }
            .buttonStyle(.plain)

            NavigationLink {
                ScheduleListView()
            } label: {
                navLabel(title: "定时唤醒",
                         detail: "\(state.config?.schedules.count ?? 0) / \(AppConfig.maxSchedules) 条",
                         icon: "clock")
            }
            .buttonStyle(.plain)

            NavigationLink {
                FirmwareConfigView()
            } label: {
                navLabel(title: "WiFi / 发送参数",
                         detail: (state.config?.ssid.isEmpty == false ? state.config?.ssid : nil) ?? "—",
                         icon: "wifi")
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func navLabel(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.sub.opacity(0.6))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - 快捷指令

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷指令 / Siri 深链")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("在「快捷指令」里放一个「打开 URL」动作：整条链接唤醒全部；带 mac 参数唤醒指定那台。也可以把动作命名成「开电脑」加到 Siri。外面用的时候走哪条线路由上面的模式决定。")
                .font(.caption)
                .foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                monoLine(shortcutURL)
                monoLine("esp32wol://wake?mac=AA:BB:CC:DD:EE:FF")
            }

            Button {
                UIPasteboard.general.string = shortcutURL
                Haptics.success()
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "已复制" : "复制深链")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Palette.bg)
                .foregroundStyle(copied ? Palette.good : Palette.accent)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func monoLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.bg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - 维护

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设备维护")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)

            HStack(spacing: 10) {
                actionButton(title: "重新对时", icon: "clock.arrow.circlepath", busy: state.isBusy("sync")) {
                    Task { await state.syncTime() }
                }
                actionButton(title: "重启 ESP32", icon: "arrow.triangle.2.circlepath", busy: state.isBusy("reboot")) {
                    confirmReboot = true
                }
            }
        }
        .card()
    }

    private func actionButton(title: String, icon: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                if busy {
                    ProgressView().tint(Palette.text).scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                }
                Text(title).font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Palette.bg)
            .foregroundStyle(Palette.text)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)

            row("应用版本", "1.4 (5)")
            row("当前线路", state.activePath.map { "\($0.label) · \(state.latency) ms" } ?? state.routeSummary)
            row("固件", (state.status?.fw).flatMap { $0.isEmpty ? nil : $0 } ?? "未连接")
            row("设备", "\(state.deviceCount) 台 · 每台 \(state.rounds) 轮")
            row("接口", "/api/status · /api/config · /api/wake · /api/logs")

            Text("魔术包由 ESP32 发出，手机只在两条路上选一条把指令送到它。所以外网能不能唤醒，取决于你能不能在外网访问到 ESP32 的 80 端口——隧道、组网、端口转发，三种都可以。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.sub)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
