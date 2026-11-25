//
//  AppState.swift
//  全局状态：登录态、设备、记录、提示条
//  服务器多入口（AppConfig.serverHosts）：域名失败自动换 IP 直连
//

import Foundation
import SwiftUI

// MARK: - 提示条

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
}

// MARK: - 状态机

@MainActor
final class AppState: ObservableObject {

    // 登录态
    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var currentUser: String
    @Published var loginError: String = ""
    @Published private(set) var loginDetail: String = ""
    @Published private(set) var loginBusy = false

    // 设备侧数据
    @Published private(set) var status: ESPStatus?
    @Published private(set) var config: ESPConfig?
    @Published private(set) var logs: [ESPLog] = []
    @Published private(set) var logTotal = 0
    @Published private(set) var pcStates: [String: PcState] = [:]
    @Published private(set) var online = false
    @Published private(set) var latency = 0
    @Published private(set) var lastError: String?
    @Published private(set) var busy: Set<String> = []

    // 提示条
    @Published var toast: Toast?

    private(set) var password: String
    private let defaults = UserDefaults.standard
    private var activeHostIndex = 0

    private enum Keys {
        static let user = "wol.user"
        static let pass = "wol.password"
        static let loggedIn = "wol.loggedIn"
        static let loggedOut = "wol.loggedOut"
    }

    init() {
        let d = UserDefaults.standard
        currentUser = d.string(forKey: Keys.user) ?? AppConfig.defaultUser
        password = Keychain.read(Keys.pass) ?? AppConfig.defaultPassword
        isLoggedIn = d.bool(forKey: Keys.loggedIn) && !password.isEmpty
    }

    // MARK: - 派生

    /// 用户主动退出过就不再自动登录（除非重新登录一次）
    var autoLoginAllowed: Bool { !defaults.bool(forKey: Keys.loggedOut) }

    var deviceCount: Int { config?.devices.count ?? 0 }
    var devices: [ESPDevice] { config?.devices ?? [] }
    var latestLog: ESPLog? { logs.first }

    /// 电脑在线状态：key 是 MAC 大写
    func pcState(for device: ESPDevice) -> PcState? {
        pcStates[device.mac.uppercased()]
    }
    var rounds: Int { config?.count ?? 3 }

    /// 走的是第几个入口（0 = 域名，1 = IP 直连），仅用于诊断文案
    var usingFallbackHost: Bool { activeHostIndex > 0 }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func begin(_ key: String) { busy.insert(key) }
    private func end(_ key: String) { busy.remove(key) }

    // MARK: - 多入口尝试

    private func attempt<T>(user: String? = nil,
                            pass: String? = nil,
                            _ work: (APIClient) async throws -> T) async throws -> T {
        let u = user ?? currentUser
        let p = pass ?? password
        var lastError: Error = APIError.transport("没有可用入口")
        for (index, host) in AppConfig.serverHosts.enumerated() {
            guard let client = APIClient(host: host, user: u, pass: p,
                                         timeout: AppConfig.requestTimeout) else { continue }
            do {
                let value = try await work(client)
                activeHostIndex = index
                return value
            } catch let e as APIError {
                lastError = e
                if case .unauthorized = e { throw e }
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    // MARK: - 登录 / 退出

    @discardableResult
    func login(user: String, pass: String) async -> Bool {
        let name = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            loginError = "账号不能空"
            return false
        }
        guard !pass.isEmpty else {
            loginError = "密码不能空"
            return false
        }

        loginBusy = true
        loginError = ""
        loginDetail = ""
        defer { loginBusy = false }

        do {
            let st = try await attempt(user: name, pass: pass) { client in
                try await client.status()
            }
            status = st
            online = true
            latency = 0
            lastError = nil
            currentUser = name
            password = pass
            defaults.set(name, forKey: Keys.user)
            defaults.set(true, forKey: Keys.loggedIn)
            defaults.set(false, forKey: Keys.loggedOut)
            Keychain.save(pass, for: Keys.pass)
            isLoggedIn = true
            Haptics.success()
            await refresh(silent: true)
            return true
        } catch {
            let msg = describe(error)
            loginError = msg
            loginDetail = detailOf(error)
            Haptics.error()
            return false
        }
    }

    func logout() {
        Keychain.save("", for: Keys.pass)
        defaults.set(false, forKey: Keys.loggedIn)
        defaults.set(true, forKey: Keys.loggedOut)
        password = ""
        isLoggedIn = false
        status = nil
        config = nil
        logs = []
        logTotal = 0
        pcStates = [:]
        online = false
        latency = 0
        lastError = nil
        loginError = ""
        loginDetail = ""
    }

    // MARK: - 拉取

    func refresh(silent: Bool = false) async {
        begin("refresh")
        defer { end("refresh") }

        let t0 = Date()
        do {
            let st = try await attempt { client in try await client.status() }
            status = st
            online = true
            latency = max(1, Int(Date().timeIntervalSince(t0) * 1000))
            lastError = nil
            if let cfg = try? await attempt({ client in try await client.config() }) {
                config = cfg
            }
            if let lg = try? await attempt({ client in try await client.logs() }) {
                logs = lg.logs
                logTotal = lg.total
            }
            if let ps = try? await attempt({ client in try await client.pcStates() }) {
                var map: [String: PcState] = [:]
                for item in ps.items { map[item.mac.uppercased()] = item }
                pcStates = map
            }
        } catch {
            online = false
            let msg = describe(error)
            lastError = msg
            if !silent { show(msg, ok: false) }
        }
    }

    private func run<T>(_ work: (APIClient) async throws -> T) async -> T? {
        do {
            let value = try await attempt(work)
            online = true
            return value
        } catch {
            online = false
            let msg = describe(error)
            lastError = msg
            show(msg, ok: false)
            return nil
        }
    }

    // MARK: - 记录

    func loadLogs() async {
        begin("logs")
        defer { end("logs") }
        guard let lg = await run({ client in try await client.logs() }) else { return }
        logs = lg.logs
        logTotal = lg.total
    }

    // MARK: - 唤醒

    func wakeAll() async {
        begin("all")
        defer { end("all") }
        guard let r = await run({ client in try await client.wakeAll() }) else {
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
            Haptics.error()
            return
        }
        announce(r, fallback: "已唤醒 \(label ?? mac)")
        await refresh(silent: true)
    }

    private func announce(_ r: WakeResult, fallback: String) {
        show(r.msg ?? fallback, ok: r.ok)
        if r.ok { Haptics.success() } else { Haptics.error() }
    }

    // MARK: - 维护动作

    /// 远程关机（电脑需在线；关机后 Win 端会自动补一次下线心跳）
    func shutdown(_ device: ESPDevice) async {
        let key = "stop:" + device.mac
        begin(key)
        defer { end(key) }
        guard let r = await run({ client in
            try await client.pcCommand(mac: device.mac, cmd: "shutdown")
        }) else {
            Haptics.error()
            return
        }
        show(r.ok ? "关机指令已下发，5 秒后执行" : (r.msg ?? "下发失败"), ok: r.ok)
        if r.ok { Haptics.success() } else { Haptics.error() }
        await refresh(silent: true)
    }

    func clearLogs() async {
        begin("clear")
        defer { end("clear") }
        guard await run({ client in try await client.clearLogs() }) != nil else { return }
        logs = []
        logTotal = 0
        show("唤醒记录已清空", ok: true)
    }

    func syncTime() async {
        begin("sync")
        defer { end("sync") }
        guard let r = await run({ client in try await client.syncTime() }) else { return }
        show(r.msg ?? "已重新发起对时", ok: true)
    }

    func reboot() async {
        begin("reboot")
        defer { end("reboot") }
        guard await run({ client in try await client.reboot() }) != nil else { return }
        status = nil
        config = nil
        online = false
        show("ESP32 重启中，约 10 秒后重新连上", ok: true)
    }

    func testConnection() async {
        await refresh(silent: false)
        if online {
            show("连接正常 · " + String(latency) + " ms", ok: true)
            Haptics.success()
        }
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
        guard let r = result else { return false }
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
        guard let r = await run({ client in try await client.saveWiFi(ssid: ssid, pass: pass) }) else {
            return false
        }
        show(r.msg ?? "WiFi 已保存", ok: r.ok)
        if r.ok { Haptics.success() }
        return r.ok
    }

    func factoryReset() async {
        begin("reset")
        defer { end("reset") }
        guard await run({ client in try await client.factoryReset() }) != nil else { return }
        status = nil
        config = nil
        logs = []
        logTotal = 0
        online = false
        show("已恢复出厂，ESP32 重启中", ok: true)
    }

    // MARK: - 深链: esp32wol://wake[?mac=..&ip=..]

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "esp32wol" else { return }
        let route = (url.host ?? url.path.replacingOccurrences(of: "/", with: "")).lowercased()
        guard route == "wake", isLoggedIn else { return }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let mac = items.first { $0.name.lowercased() == "mac" }?.value ?? ""
        let ip = items.first { $0.name.lowercased() == "ip" }?.value ?? ""

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
                return "账号或密码不对"
            }
            return e.errorDescription ?? "未知错误"
        }
        return NetReason.of(error)
    }

    private func detailOf(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e {
            case .unauthorized:
                return "服务器回了 401：账号或密码不对"
            case .transport(let m):
                return "网络层失败：" + m
            case .http(let code, let body):
                return "HTTP " + String(code) + " " + body
            case .decode(let m):
                return "返回内容解析失败：" + m
            case .badURL:
                return "入口地址配置异常"
            }
        }
        return NetReason.of(error)
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
