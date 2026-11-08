//
//  LogsView.swift
//  唤醒记录（ESP32 闪存里的最近 30 条）
//

import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    summary
                    if state.logs.isEmpty {
                        emptyCard
                    } else {
                        ForEach(state.logs) { entry in
                            LogRow(entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("唤醒记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        confirmClear = true
                    } label: {
                        Text("清空").font(.footnote.weight(.medium))
                    }
                    .disabled(state.logs.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.tap()
                        Task { await state.loadLogs() }
                    } label: {
                        if state.isBusy("logs") {
                            ProgressView().tint(Palette.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(state.isBusy("logs"))
                }
            }
            .confirmationDialog("清空全部唤醒记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    Task { await state.clearLogs() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删掉 ESP32 闪存里的全部记录，累计次数归零。设备配置和密码不受影响。")
            }
            .task { await state.loadLogs() }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("累计 \(state.logTotal) 次")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("只保留最近 30 条 · 默认每天 00:00 自动清空")
                    .font(.caption2)
                    .foregroundStyle(Palette.sub)
            }
            Spacer(minLength: 0)
            Text("\(state.logs.count)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Palette.accent.opacity(0.12))
                .clipShape(Capsule())
        }
        .card()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有记录")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("每次唤醒（手动、单台、定时）都会在 ESP32 里留一条：时间 / 来源 / 目标 / 包数 / 成败。")
                .font(.caption)
                .foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

struct LogRow: View {
    let entry: ESPLog

    private var badgeColor: Color {
        entry.src.contains("定时") ? Color(red: 0.72, green: 0.58, blue: 1.0) : Palette.accent
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Circle()
                    .fill(entry.succeeded ? Palette.good : Palette.bad)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(Palette.stroke)
                    .frame(width: 1)
            }
            .frame(width: 7)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(entry.dev)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(entry.src)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.14))
                        .clipShape(Capsule())
                    Spacer(minLength: 0)
                    Text(entry.t)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.sub)
                }
                HStack(spacing: 8) {
                    if !entry.mac.isEmpty {
                        Text(entry.mac)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.sub.opacity(0.85))
                    }
                    Text("\(entry.pk) 包")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.sub.opacity(0.85))
                    Text(entry.succeeded ? "已发出" : "失败")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.succeeded ? Palette.good : Palette.bad)
                }
            }
        }
        .padding(14)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.stroke, lineWidth: 1)
        )
    }
}
