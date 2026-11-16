//
//  AppState.swift
//  全局状态：双地址（局域网 / 外网）、自动回退、设备、记录、提示条
//

import Foundation
import SwiftUI

// MARK: - 线路

enum NetworkPath: String, CaseIterable, Identifiable {
    case lan, wan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lan: return "局域网"
        case .wan: return "外网"
        }
    }

    var symbol: String {
        switch self {
        case .lan: return "house.fill"
        case .wan: return "globe"
        }
    }
}

enum RouteMode: String, CaseIterable, Identifiable {
    case auto, lanOnly, wanOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动"
        case .lanOnly: return "仅局域网"
        case .wanOnly: return "仅外网"
        }
    }
}

/// 单条线路的探测结果
struct PathProbe: Identifiable, Equatable {
    let path: NetworkPath
    let host: String
    let ok: Bool
    let ms: Int
    let note: String

    var id: String { path.rawValue }
}

// MARK: - 提示条

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
}

// MARK: - 状态机

@MainActor
final class AppState: ObservableObject {

    // 连接参数
    @Published var lanHost: String
    @Published var wanHost: String
    @Published var routeMode: RouteMode
    @Published var user: String
    @Published var password: String

    // 设备侧数据
    @Published private(set) var status: ESPStatus?
    @Published private(set) var config: ESPConfig?
    @Published private(set) var logs: [ESPLog] = []
    @Published private(set) var logTotal = 0
    @Published private(set) var online = false
    @Published private(set) var lastError: String?
    @Published private(set) var busy: Set<String> = []

    // 线路状态
    @Published private(set) var activePath: NetworkPath?
    @Published private(set) var latency = 0
    @Published private(set) var pathErrors: [String: String] = [:]
    @Published private(set) var probes: [PathProbe] = []

    // 提示条
    @Published var toast: Toast?

    private let defaults = UserDefaults.standard
    /// 局域网刚失败过就先跳一会儿，别每次刷新都白等 2 秒
    private var lanSkipUntil = Date.distantPast

    private enum Keys {
        static let lan = "wol.lan"
        static let wan = "wol.wan"
        static let legacHost = "wol.host"
        static let user = "wol.user"
        static let pass = "wol.password"
        static let mode = "wol.routeMode"
    }

    init() {
        let d = UserDefaults.standard
        lanHost = d.string(forKey: Keys.lan)
            ?? d.string(forKey: Keys.legacHost)
            ?? AppConfig.defaultLanHost
        wanHost = d.string(forKey: Keys.wan) ?? AppConfig.defaultWanHost
        user = d.string(forKey: Keys.user) ?? AppConfig.defaultUser
        password = Keychain.read(Keys.pass) ?? AppConfig.defaultPassword
        routeMode = RouteMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .auto
    }

    // MARK: - 派生

    var deviceCount: Int { config?.devices.count ?? 0 }
    var devices: [ESPDevice] { config?.devices ?? [] }
    var latestLog: ESPLog? { logs.first }
    var rounds: Int { config?.count ?? 3 }

    /// 密码还空着：固件那边设过访问密码的话，所有请求都会 401
    var needsPassword: Bool { password.trimmingCharacters(in: .whitespaces).isEmpty }

    private var trimmedLan: String { lanHost.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedWan: String { wanHost.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 当前要试的地址，顺序就是回退顺序
    private var targets: [(NetworkPath, String)] {
        var list: [(NetworkPath, String)] = []
        let lanReady = routeMode != .wanOnly && !trimmedLan.isEmpty
        if lanReady && Date() >= lanSkipUntil {
            list.append((.lan, trimmedLan))
        }
        if routeMode != .lanOnly && !trimmedWan.isEmpty {
            list.append((.wan, trimmedWan))
        }
        // 手动锁定单条线路时，冷却不影响
        if list.isEmpty, lanReady {
            list.append((.lan, trimmedLan))
        }
        return list
    }

    private var allEndpoints: [(NetworkPath, String)] {
        var list: [(NetworkPath, String)] = []
        if !trimmedLan.isEmpty { list.append((.lan, trimmedLan)) }
        if !trimmedWan.isEmpty { list.append((.wan, trimmedWan)) }
        return list
    }

    /// 状态卡副标题：自动模式下说明会怎么回退
    var routeSummary: String {
        switch routeMode {
        case .auto:
            if trimmedWan.isEmpty { return "仅局域网" }
            return activePath == .wan ? "外网 · 局域网不通" : "局域网优先"
        case .lanOnly:
            return "锁定局域网"
        case .wanOnly:
            return "锁定外网"
        }
    }

    private func makeClient(_ host: String, _ path: NetworkPath) -> APIClient? {
        APIClient(host: host, user: user, pass: password,
                  timeout: path == .lan ? AppConfig.lanTimeout : AppConfig.wanTimeout)
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func begin(_ key: String) { busy.insert(key) }
    private func end(_ key: String) { busy.remove(key) }

    // MARK: - 设置项绑定（写入即落盘）

    var lanHostBinding: Binding<String> {
        Binding(
            get: { self.lanHost },
            set: { value in
                self.lanHost = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.defaults.set(self.lanHost, forKey: Keys.lan)
                self.lanSkipUntil = .distantPast
            }
        )
    }

    var wanHostBinding: Binding<String> {
        Binding(
            get: { self.wanHost },
            set: { value in
                self.wanHost = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.defaults.set(self.wanHost, forKey: Keys.wan)
            }
        )
    }

    var routeModeBinding: Binding<RouteMode> {
        Binding(
            get: { self.routeMode },
            set: { value in
                self.routeMode = value
                self.defaults.set(value.rawValue, forKey: Keys.mode)
                self.lanSkipUntil = .distantPast
                Task { await self.refresh(silent: true) }
            }
        )
    }

    var userBinding: Binding<String> {
        Binding(
            get: { self.user },
            set: { value in
                self.user = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.defaults.set(self.user, forKey: Keys.user)
            }
        )
    }

    var passwordBinding: Binding<String> {
        Binding(
            get: { self.password },
            set: { value in
                self.password = value
                Keychain.save(value, for: Keys.pass)
            }
        )
    }

    // MARK: - 拉取（带线路回退）

    func refresh(silent: Bool = false) async {
        let list = targets
        guard !list.isEmpty else {
            online = false
            activePath = nil
            lastError = "还没填地址：局域网或外网至少填一个"
            if !silent { show("先到设置里填一个地址", ok: false) }
            return
        }
        begin("refresh")
        defer { end("refresh") }

        var failure = ""
        for (path, host) in list {
            guard let c = makeClient(host, path) else {
                pathErrors[path.rawValue] = "地址格式不对"
                failure = "\(path.label)：地址格式不对"
                continue
            }
            let t0 = Date()
            do {
                let st = try await c.status()
                let ms = max(1, Int(Date().timeIntervalSince(t0) * 1000))
                apply(path: path, latency: ms, newStatus: st)
                if let cfg = try? await c.config() { config = cfg }
                if let lg = try? await c.logs() {
                    logs = lg.logs
                    logTotal = lg.total
                }
                return
            } catch {
                if path == .lan { lanSkipUntil = Date().addingTimeInterval(AppConfig.lanCooldown) }
                let msg = describe(error)
                pathErrors[path.rawValue] = msg
                failure = list.count > 1 ? "\(path.label)：\(msg)" : msg
            }
        }

        online = false
        activePath = nil
        latency = 0
        lastError = failure.isEmpty ? "连不上设备" : failure
        if !silent { show(lastError ?? "连不上设备", ok: false) }
    }

    private func apply(path: NetworkPath, latency ms: Int, newStatus: ESPStatus) {
        status = newStatus
        online = true
        activePath = path
        latency = ms
        lastError = nil
        pathErrors[path.rawValue] = nil
        if path == .lan { lanSkipUntil = .distantPast }
    }

    /// 依次试候选地址，第一次成功就返回
    private func run<T>(_ work: (APIClient) async throws -> T) async -> T? {
        let list = targets
        guard !list.isEmpty else {
            show("先到设置里填一个地址", ok: false)
            return nil
        }
        for (path, host) in list {
            guard let c = makeClient(host, path) else { continue }
            let t0 = Date()
            do {
                let value = try await work(c)
                let ms = max(1, Int(Date().timeIntervalSince(t0) * 1000))
                activePath = path
                latency = ms
                pathErrors[path.rawValue] = nil
                if path == .lan { lanSkipUntil = .distantPast }
                return value
            } catch let e as APIError {
                pathErrors[path.rawValue] = describe(e)
                if case .unauthorized = e { break }
                if path == .lan { lanSkipUntil = Date().addingTimeInterval(AppConfig.lanCooldown) }
                continue
            } catch {
                pathErrors[path.rawValue] = describe(error)
                if path == .lan { lanSkipUntil = Date().addingTimeInterval(AppConfig.lanCooldown) }
                continue
            }
        }
        return nil
    }

    private var firstPathError: String {
        if let e = pathErrors[NetworkPath.lan.rawValue] { return "局域网：\(e)" }
        if let e = pathErrors[NetworkPath.wan.rawValue] { return "外网：\(e)" }
        return lastError ?? "连不上设备"
    }

    // MARK: - 记录

    func loadLogs() async {
        begin("logs")
        defer { end("logs") }
        guard let lg = await run({ client in try await client.logs() }) else {
            show(firstPathError, ok: false)
            return
        }
        logs = lg.logs
        logTotal = lg.total
    }

    // MARK: - 唤醒

    func wakeAll() async {
        begin("all")
        defer { end("all") }
        guard let r = await run({ client in try await client.wakeAll() }) else {
            show(firstPathError, ok: false)
            Haptics.error()
            return
        }
        announce(r, fallback: "魔术包已发出")
        await refresh(silent: true)
    }

    func wake(_ device: ESPDevice) async {
        await wake(mac: device.mac, ip: device.ip, label: device.displayName)
    }

    func wake(mac: String, ip: String = "", label: String? = nil) async {
        let key = "dev:" + mac
        begin(key)
        defer { end(key) }
        guard let r = await run({ client in try await client.wake(mac: mac, ip: ip) }) else {
            show(firstPathError, ok: false)
            Haptics.error()
            return
        }
        announce(r, fallback: "已唤醒 \(label ?? mac)")
        await refresh(silent: true)
    }

    private func announce(_ r: WakeResult, fallback: String) {
        var text = r.msg ?? fallback
        if r.ok, let p = activePath {
            text += " · 经" + p.label
        }
        show(text, ok: r.ok)
        if r.ok { Haptics.success() } else { Haptics.error() }
    }

    // MARK: - 维护动作

    func clearLogs() async {
        begin("clear")
        defer { end("clear") }
        let result = await run({ client in try await client.clearLogs() })
        guard result != nil else {
            show(firstPathError, ok: false)
            return
        }
        logs = []
        logTotal = 0
        show("唤醒记录已清空", ok: true)
    }

    func syncTime() async {
        begin("sync")
        defer { end("sync") }
        let result = await run({ client in try await client.syncTime() })
        guard let r = result else {
            show(firstPathError, ok: false)
            return
        }
        show(r.msg ?? "已重新发起对时", ok: true)
    }

    func reboot() async {
        begin("reboot")
        defer { end("reboot") }
        let result = await run({ client in try await client.reboot() })
        guard result != nil else {
            show(firstPathError, ok: false)
            return
        }
        status = nil
        config = nil
        online = false
        activePath = nil
        show("ESP32 重启中，约 10 秒后重新连上", ok: true)
    }

    // MARK: - 写固件配置（全量替换，没传的字段沿用当前值）

    private var fallbackPort: Int { config?.port ?? 9 }
    private var fallbackCount: Int { config?.count ?? 3 }
    private var fallbackLogAC: Int { config?.logac ?? 1 }
    private var fallbackLogCH: Int { config?.logch ?? 0 }
    private var fallbackLogCM: Int { config?.logcm ?? 0 }
    private var fallbackDevices: [ESPDevice] { config?.devices ?? [] }
    private var fallbackSchedules: [ESPSchedule] { config?.schedules ?? [] }

    @discardableResult
    func pushConfig(devices: [ESPDevice]? = nil,
                    schedules: [ESPSchedule]? = nil,
                    port: Int? = nil,
                    count: Int? = nil,
                    logAutoClear: Bool? = nil,
                    logHour: Int? = nil,
                    logMin: Int? = nil) async -> Bool {
        let devs = devices ?? fallbackDevices
        let scheds = schedules ?? fallbackSchedules
        let p = port ?? fallbackPort
        let c = count ?? fallbackCount
        let autoClear = logAutoClear ?? (fallbackLogAC != 0)
        let hour = logHour ?? fallbackLogCH
        let minute = logMin ?? fallbackLogCM

        begin("save")
        defer { end("save") }

        let result = await run({ client in
            try await client.saveConfig(port: p, count: c, logAutoClear: autoClear,
                                        logHour: hour, logMin: minute,
                                        devices: devs, schedules: scheds)
        })
        guard let r = result else {
            show(firstPathError, ok: false)
            Haptics.error()
            return false
        }
        if r.ok {
            show(r.msg ?? "已写入闪存", ok: true)
            Haptics.success()
            await refresh(silent: true)
        } else {
            show(r.msg ?? "保存失败", ok: false)
            Haptics.error()
        }
        return r.ok
    }

    @discardableResult
    func saveWiFi(ssid: String, pass: String) async -> Bool {
        begin("wifi")
        defer { end("wifi") }
        let result = await run({ client in try await client.saveWiFi(ssid: ssid, pass: pass) })
        guard let r = result else {
            show(firstPathError, ok: false)
            return false
        }
        show(r.msg ?? "WiFi 已保存", ok: r.ok)
        if r.ok { Haptics.success() }
        return r.ok
    }

    func factoryReset() async {
        begin("reset")
        defer { end("reset") }
        let result = await run({ client in try await client.factoryReset() })
        guard result != nil else {
            show(firstPathError, ok: false)
            return
        }
        status = nil
        config = nil
        logs = []
        logTotal = 0
        online = false
        activePath = nil
        show("已恢复出厂，ESP32 重启中", ok: true)
    }

    // MARK: - 线路探测

    /// 测单条线路
    func testPath(_ path: NetworkPath) async {
        let host = path == .lan ? trimmedLan : trimmedWan
        guard !host.isEmpty else {
            show("\(path.label)地址还空着", ok: false)
            return
        }
        begin("probe:" + path.rawValue)
        defer { end("probe:" + path.rawValue) }
        let probe = await probeOne(path, host)
        upsert(probe)
        if probe.ok {
            Haptics.success()
            await refresh(silent: true)
        } else {
            Haptics.error()
        }
    }

    /// 两条一起测，出结果表
    func diagnose() async {
        guard !allEndpoints.isEmpty else {
            show("先填地址", ok: false)
            return
        }
        begin("diag")
        defer { end("diag") }
        probes = []
        for (path, host) in allEndpoints {
            let probe = await probeOne(path, host)
            probes.append(probe)
        }
        if probes.contains(where: { $0.ok }) {
            await refresh(silent: true)
        }
    }

    private func probeOne(_ path: NetworkPath, _ host: String) async -> PathProbe {
        guard let c = makeClient(host, path) else {
            return PathProbe(path: path, host: host, ok: false, ms: 0, note: "地址格式不对")
        }
        let t0 = Date()
        do {
            let st = try await c.status()
            let ms = max(1, Int(Date().timeIntervalSince(t0) * 1000))
            let note = st.fw.isEmpty ? "通" : "固件 " + st.fw
            return PathProbe(path: path, host: host, ok: true, ms: ms, note: note)
        } catch {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            return PathProbe(path: path, host: host, ok: false, ms: ms, note: describe(error))
        }
    }

    private func upsert(_ probe: PathProbe) {
        if let idx = probes.firstIndex(where: { $0.path == probe.path }) {
            probes[idx] = probe
        } else {
            probes.append(probe)
        }
    }

    func probeResult(_ path: NetworkPath) -> PathProbe? {
        probes.first { $0.path == path }
    }

    func testConnection() async {
        await refresh(silent: false)
        if online {
            let where_ = activePath?.label ?? "设备"
            show("连接正常 · \(where_) · \(latency) ms", ok: true)
            Haptics.success()
        }
    }

    // MARK: - 深链: esp32wol://wake[?mac=..&ip=..]
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "esp32wol" else { return }
        let route = (url.host ?? url.path.replacingOccurrences(of: "/", with: "")).lowercased()
        guard route == "wake" else { return }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let mac = items.first { $0.name.lowercased() == "mac" }?.value ?? ""
        let ip  = items.first { $0.name.lowercased() == "ip" }?.value ?? ""

        Task {
            await refresh(silent: true)
            if mac.isEmpty {
                await wakeAll()
            } else if let d = config?.devices.first(where: { $0.mac.caseInsensitiveCompare(mac) == .orderedSame }) {
                await wake(d)
            } else {
                await wake(mac: mac, ip: ip)
            }
        }
    }

    // MARK: - 内部

    private func describe(_ error: Error) -> String {
        if let e = error as? APIError {
            if case .unauthorized = e {
                if password.isEmpty {
                    return "设备要登录，App 里还没填密码（设置 → 密码）"
                }
                return "用户名或密码不对 (401)"
            }
            return e.errorDescription ?? "未知错误"
        }
        return error.localizedDescription
    }

    private func show(_ text: String, ok: Bool) {
        let t = Toast(text: text, ok: ok)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self.toast == t { self.toast = nil }
        }
    }
}
