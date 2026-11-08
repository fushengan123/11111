//
//  ScheduleListView.swift
//  定时唤醒：时间 + 星期位图 + 目标，最多 8 条（对应固件网页的「定时唤醒」）
//

import SwiftUI

struct ScheduleListView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ESPSchedule] = []
    @State private var loaded = false

    @State private var showEditor = false
    @State private var editingIndex: Int? = nil
    @State private var draftTime = Date()
    @State private var draftDays = 0
    @State private var draftTarget = -1
    @State private var draftEnabled = true

    private let dayNames = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    row(index: pair.offset, schedule: pair.element)
                }

                if items.isEmpty { emptyCard }

                if items.count < AppConfig.maxSchedules { addButton }

                saveBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("定时唤醒")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) { editor }
        .onAppear(perform: load)
    }

    // MARK: - 片段

    private var header: some View {
        HStack {
            Text("到点由 ESP32 自己发包 · 需联网对时")
                .font(.caption2)
                .foregroundStyle(Palette.sub)
            Spacer()
            Text("\(items.count) / \(AppConfig.maxSchedules)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.sub)
        }
        .padding(.horizontal, 4)
    }

    private func row(index: Int, schedule: ESPSchedule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(schedule.timeText)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(schedule.isOn ? Palette.text : Palette.sub)
                    if !schedule.isOn {
                        Text("停用")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.sub)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.bg)
                            .clipShape(Capsule())
                    }
                }
                Text(schedule.daysText + " · " + targetLabel(schedule.target))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.sub)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                toggle(index: index)
            } label: {
                Text(schedule.isOn ? "停用" : "启用")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.bg)
                    .foregroundStyle(schedule.isOn ? Palette.sub : Palette.good)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                beginEdit(index: index, schedule: schedule)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
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
        Text("还没有定时。加一条：选时间和星期，再选唤醒哪台（或全部）。保存后写进 ESP32，掉电不丢。")
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
            draftTime = dateFrom(hour: 7, minute: 0)
            draftDays = 0
            draftTarget = -1
            draftEnabled = true
            showEditor = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("添加定时")
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
                let ok = await state.pushConfig(schedules: items)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("时间")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.sub)
                        DatePicker("", selection: $draftTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .background(Palette.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("星期（可多选；「每天」= 不限制）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.sub)
                        HStack(spacing: 6) {
                            dayChip(title: "每", bit: 0)
                            ForEach(0..<7, id: \.self) { k in
                                dayChip(title: dayNames[k], bit: 1 << k)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("目标设备")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.sub)
                        Picker("目标设备", selection: $draftTarget) {
                            Text("全部 \(state.devices.count) 台").tag(-1)
                            ForEach(Array(state.devices.enumerated()), id: \.offset) { pair in
                                Text(pair.element.displayName).tag(pair.offset)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .background(Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Toggle(isOn: $draftEnabled) {
                        Text("启用这条定时")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.text)
                    }
                    .tint(Palette.accent)
                    .padding(14)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if state.devices.isEmpty {
                        Text("ESP32 里还没有设备，这条定时只能唤醒「全部」。先去设备管理加一台。")
                            .font(.caption2)
                            .foregroundStyle(Palette.sub.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(editingIndex == nil ? "添加定时" : "编辑定时")
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

    private func dayChip(title: String, bit: Int) -> some View {
        let on: Bool = bit == 0 ? (draftDays == 0) : (draftDays & bit) != 0
        return Button {
            Haptics.tap()
            toggleDay(bit)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? Palette.accent : Palette.card)
                .foregroundStyle(on ? Palette.ink : Palette.sub)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 逻辑

    private func load() {
        guard !loaded else { return }
        loaded = true
        items = state.config?.schedules ?? []
    }

    private func targetLabel(_ target: Int) -> String {
        if target < 0 { return "全部" }
        let devices = state.devices
        if target < devices.count { return devices[target].displayName }
        return "设备 #\(target + 1)"
    }

    private func toggle(index: Int) {
        guard index < items.count else { return }
        let s = items[index]
        items[index] = ESPSchedule(enabled: s.isOn ? 0 : 1,
                                   hour: s.hour, minute: s.minute,
                                   days: s.days, target: s.target)
    }

    private func beginEdit(index: Int, schedule: ESPSchedule) {
        editingIndex = index
        draftTime = dateFrom(hour: schedule.hour, minute: schedule.minute)
        draftDays = schedule.days
        draftTarget = schedule.target
        draftEnabled = schedule.isOn
        showEditor = true
    }

    private func toggleDay(_ bit: Int) {
        if bit == 0 {
            draftDays = 0
            return
        }
        if draftDays == 0 {
            draftDays = bit
        } else if (draftDays & bit) != 0 {
            draftDays &= ~bit
        } else {
            draftDays |= bit
        }
    }

    private func commit() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
        let schedule = ESPSchedule(enabled: draftEnabled ? 1 : 0,
                                   hour: comps.hour ?? 0,
                                   minute: comps.minute ?? 0,
                                   days: draftDays,
                                   target: draftTarget)
        if let idx = editingIndex, idx < items.count {
            items[idx] = schedule
        } else {
            items.append(schedule)
            editingIndex = nil
        }
        showEditor = false
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }
}
