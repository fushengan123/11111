//
//  FirmwareConfigView.swift
//  WiFi、发送参数、日志策略、恢复出厂 —— 对应固件网页剩下那几块
//

import SwiftUI

struct FirmwareConfigView: View {
    @EnvironmentObject private var state: AppState

    @State private var ssid = ""
    @State private var wifiPass = ""
    @State private var portText = "9"
    @State private var count = 3
    @State private var logAutoClear = true
    @State private var clearTime = Date()
    @State private var confirmReset = false
    @State private var loaded = false
    @State private var portError = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                wifiCard
                sendCard
                logCard
                resetCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("固件设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("恢复出厂设置？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("清空并重启", role: .destructive) {
                Task { await state.factoryReset() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清掉 WiFi、设备、定时、访问密码和全部记录，ESP32 重启后回到热点模式（ESP32-WOL / 12345678）。")
        }
        .onAppear(perform: load)
    }

    // MARK: - WiFi

    private var wifiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("WiFi", subtitle: state.config?.ssid.isEmpty == false
                  ? "当前：\(state.config?.ssid ?? "")"
                  : "还没读到当前网络")

            FieldRow(title: "SSID（2.4GHz）", placeholder: "家里的 WiFi 名", text: $ssid, mono: false)
            FieldRow(title: "密码", placeholder: "WiFi 密码", text: $wifiPass,
                     keyboard: .asciiCapable, mono: false, secure: true)

            Button {
                Haptics.tap()
                Task { _ = await state.saveWiFi(ssid: ssid, pass: wifiPass) }
            } label: {
                actionLabel(busy: state.isBusy("wifi"), text: "保存 WiFi", icon: "wifi")
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy("wifi"))

            Text("ESP32 只支持 2.4GHz。保存后它会断开重连，约 5 秒；连不上会自动开热点 ESP32-WOL（密码 12345678）。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: - 发送参数

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("魔术包发送", subtitle: "UDP 端口 + 重复轮数")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UDP 端口")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.sub)
                    TextField("9", text: $portText)
                        .keyboardType(.numberPad)
                        .inputShell()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("轮数")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.sub)
                    HStack(spacing: 10) {
                        stepButton("minus") { if count > 1 { count -= 1 } }
                        Text("\(count)")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.text)
                            .frame(minWidth: 24)
                        stepButton("plus") { if count < 20 { count += 1 } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Palette.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if !portError.isEmpty {
                Text(portError)
                    .font(.caption2)
                    .foregroundStyle(Palette.bad)
            }

            Button {
                Haptics.tap()
                saveSend()
            } label: {
                actionLabel(busy: state.isBusy("save"), text: "保存发送参数", icon: "paperplane")
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy("save"))

            Text("默认 9。有些网卡只认 7，唤醒无反应可以换 7 试试。轮数越大越稳，也越耗时（每轮 80ms 间隔）。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: - 日志策略

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("唤醒记录", subtitle: "每天到点自动清空，只留当天")

            Toggle(isOn: $logAutoClear) {
                Text("每天自动清空")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.accent)

            if logAutoClear {
                DatePicker("清空时刻", selection: $clearTime, displayedComponents: .hourAndMinute)
                    .font(.footnote)
                    .foregroundStyle(Palette.text)
                    .datePickerStyle(.compact)
            }

            Button {
                Haptics.tap()
                let comps = Calendar.current.dateComponents([.hour, .minute], from: clearTime)
                Task {
                    _ = await state.pushConfig(logAutoClear: logAutoClear,
                                               logHour: comps.hour ?? 0,
                                               logMin: comps.minute ?? 0)
                }
            } label: {
                actionLabel(busy: state.isBusy("save"), text: "保存记录策略", icon: "clock")
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy("save"))

            if let cfg = state.config {
                Text(currentPolicyText(cfg))
                    .font(.caption2)
                    .foregroundStyle(Palette.sub.opacity(0.85))
            }
        }
        .card()
    }

    // MARK: - 恢复出厂

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("危险区")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.bad)

            Button {
                Haptics.tap()
                confirmReset = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("恢复出厂设置")
                        .font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(Palette.bad.opacity(0.12))
                .foregroundStyle(Palette.bad)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("清空 WiFi、设备、定时、访问密码和全部记录，然后重启。做完要去热点 ESP32-WOL 重新配。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: - 零件

    private func title(_ text: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Palette.sub)
        }
    }

    private func actionLabel(busy: Bool, text: String, icon: String) -> some View {
        HStack(spacing: 7) {
            if busy {
                ProgressView().tint(Palette.ink).scaleEffect(0.8)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(busy ? "写入中…" : text)
                .font(.footnote.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.accent)
        .foregroundStyle(Palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Palette.card)
                .foregroundStyle(Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 逻辑

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let cfg = state.config else { return }
        ssid = cfg.ssid
        portText = String(cfg.port)
        count = cfg.count
        logAutoClear = cfg.logAutoClear
        var comps = DateComponents()
        comps.hour = cfg.logch
        comps.minute = cfg.logcm
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        clearTime = Calendar.current.date(from: comps) ?? Date()
    }

    private func currentPolicyText(_ cfg: ESPConfig) -> String {
        let policy = cfg.logAutoClear ? "每天 " + cfg.logClearText + " 清空" : "不自动清空"
        return "当前：" + policy + "｜累计 " + String(state.logTotal) + " 次"
    }

    private func saveSend() {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value >= 1, value <= 65535 else {
            portError = "端口要是 1–65535 之间的整数"
            return
        }
        portError = ""
        Task { _ = await state.pushConfig(port: value, count: count) }
    }
}
