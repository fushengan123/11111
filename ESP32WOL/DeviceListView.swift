//
//  DeviceListView.swift
//  设备管理：增删改，整包写回 ESP32 闪存（对应固件网页的「设备列表」）
//

import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ESPDevice] = []
    @State private var loaded = false

    @State private var showEditor = false
    @State private var editingIndex: Int? = nil
    @State private var draftName = ""
    @State private var draftMac = ""
    @State private var draftIp = ""
    @State private var draftError = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    row(index: pair.offset, device: pair.element)
                }

                if items.isEmpty { emptyCard }

                if items.count < AppConfig.maxDevices {
                    addButton
                }

                saveBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("设备管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) { editor }
        .onAppear(perform: load)
    }

    // MARK: - 片段

    private var header: some View {
        HStack {
            Text("存在 ESP32 闪存里 · 最多 \(AppConfig.maxDevices) 台")
                .font(.caption2)
                .foregroundStyle(Palette.sub)
            Spacer()
            Text("\(items.count) / \(AppConfig.maxDevices)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.sub)
        }
        .padding(.horizontal, 4)
    }

    private func row(index: Int, device: ESPDevice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(device.mac)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.sub)
                if !device.ip.isEmpty {
                    Text("指定 " + device.ip)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.sub.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                beginEdit(index: index, device: device)
            } label: {
                Text("编辑")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.bg)
                    .foregroundStyle(Palette.accent)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                items.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Palette.bg)
                    .foregroundStyle(Palette.bad)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.stroke, lineWidth: 1)
        )
    }

    private var emptyCard: some View {
        Text("还没有设备。点下面「添加设备」填名称 + MAC，保存后会写到 ESP32 闪存。")
            .font(.caption)
            .foregroundStyle(Palette.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.card.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            )
    }

    private var addButton: some View {
        Button {
            Haptics.tap()
            editingIndex = nil
            draftName = ""
            draftMac = ""
            draftIp = ""
            draftError = ""
            showEditor = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("添加设备")
                    .font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Palette.card)
            .foregroundStyle(Palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    private var saveBar: some View {
        Button {
            Haptics.tap()
            Task {
                let ok = await state.pushConfig(devices: items)
                if ok { dismiss() }
            }
        } label: {
            HStack(spacing: 8) {
                if state.isBusy("save") {
                    ProgressView().tint(Palette.ink).scaleEffect(0.85)
                } else {
                    Image(systemName: "internaldrive")
                }
                Text(state.isBusy("save") ? "写入中…" : "保存到 ESP32")
                    .font(.footnote.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Palette.accent)
            .foregroundStyle(Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(state.isBusy("save"))
        .padding(.top, 4)
    }

    // MARK: - 编辑弹窗

    private var editor: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FieldRow(title: "名称", placeholder: "客厅电脑", text: $draftName, mono: false)
                    FieldRow(title: "MAC（必填）", placeholder: "AA:BB:CC:DD:EE:FF", text: $draftMac)
                    FieldRow(title: "目标 IP（可选）", placeholder: "留空 = 广播", text: $draftIp)

                    if !draftError.isEmpty {
                        Text(draftError)
                            .font(.caption)
                            .foregroundStyle(Palette.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("MAC 支持 AA:BB:CC:DD:EE:FF、aa-bb-cc-dd-ee-ff、aabbccddeeff 三种写法，保存时统一成冒号格式。IP 留空就走 255.255.255.255 广播。")
                        .font(.caption2)
                        .foregroundStyle(Palette.sub.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(editingIndex == nil ? "添加设备" : "编辑设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showEditor = false }
                        .font(.footnote)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("确定") { commit() }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    // MARK: - 逻辑

    private func load() {
        guard !loaded else { return }
        loaded = true
        items = state.devices
    }

    private func beginEdit(index: Int, device: ESPDevice) {
        editingIndex = index
        draftName = device.name
        draftMac = device.mac
        draftIp = device.ip
        draftError = ""
        showEditor = true
    }

    private func commit() {
        let mac = ESPDevice.normalized(mac: draftMac)
        guard ESPDevice.validate(mac: mac) else {
            draftError = "MAC 格式不对，需要 12 位十六进制"
            return
        }
        let device = ESPDevice(name: draftName.trimmingCharacters(in: .whitespaces),
                               mac: mac,
                               ip: draftIp.trimmingCharacters(in: .whitespaces))
        if let idx = editingIndex, idx < items.count {
            items[idx] = device
        } else {
            items.append(device)
        }
        showEditor = false
    }
}
