//
//  Models.swift
//  ESP32 WOL 远程开机 — 数据模型
//

import Foundation

// MARK: - GET /api/status

struct ESPStatus: Codable, Equatable {
    let sta: String
    let ip: String
    let apIP: String
    let rssi: Int
    let fw: String
    let time: String

    enum CodingKeys: String, CodingKey {
        case sta, ip, rssi, fw, time
        case apIP = "ap_ip"
    }

    init(sta: String = "", ip: String = "", apIP: String = "", rssi: Int = 0, fw: String = "", time: String = "") {
        self.sta = sta
        self.ip = ip
        self.apIP = apIP
        self.rssi = rssi
        self.fw = fw
        self.time = time
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sta  = (try? c.decode(String.self, forKey: .sta))  ?? ""
        ip   = (try? c.decode(String.self, forKey: .ip))   ?? ""
        apIP = (try? c.decode(String.self, forKey: .apIP)) ?? ""
        rssi = (try? c.decode(Int.self,    forKey: .rssi)) ?? 0
        fw   = (try? c.decode(String.self, forKey: .fw))   ?? ""
        time = (try? c.decode(String.self, forKey: .time)) ?? ""
    }

    /// 固件没连上路由器时 ip 为空串
    var isOnline: Bool { !ip.isEmpty }

    /// -30 ~ -95 dBm 折成 1~4 格
    var signalBars: Int {
        switch rssi {
        case 0: return 0
        case ...(-85): return 1
        case (-84)...(-74): return 2
        case (-73)...(-63): return 3
        default: return 4
        }
    }

    /// 信号环用的 0~1 强度：-100dBm 见底，-40dBm 满格
    var quality: Double {
        guard rssi < 0 else { return 0 }
        let q = (Double(rssi) + 100.0) / 60.0
        return min(1.0, max(0.0, q))
    }
}

// MARK: - GET /api/config

struct ESPDevice: Codable, Identifiable, Hashable {
    let name: String
    let mac: String
    let ip: String

    var id: String { "\(name)|\(mac)|\(ip)" }
    var displayName: String { name.isEmpty ? mac : name }

    /// 固件 dev{i} 的格式：名称|MAC|IP
    var formValue: String { "\(name)|\(mac)|\(ip)" }

    var isMacValid: Bool { ESPDevice.validate(mac: mac) }

    /// 接受 AA:BB:CC:DD:EE:FF / aa-bb-cc-dd-ee-ff / aabbccddeeff
    static func validate(mac: String) -> Bool {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard cleaned.count == 12 else { return false }
        return cleaned.allSatisfy { $0.isHexDigit }
    }

    /// 统一成 AA:BB:CC:DD:EE:FF
    static func normalized(mac: String) -> String {
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard cleaned.count == 12 else { return mac.trimmingCharacters(in: .whitespaces) }
        var parts: [String] = []
        var idx = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(idx, offsetBy: 2)
            parts.append(String(cleaned[idx..<next]))
            idx = next
        }
        return parts.joined(separator: ":")
    }

    init(name: String, mac: String, ip: String = "") {
        self.name = name
        self.mac = mac
        self.ip = ip
    }

    enum CodingKeys: String, CodingKey { case name, mac, ip }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        mac  = (try? c.decode(String.self, forKey: .mac))  ?? ""
        ip   = (try? c.decode(String.self, forKey: .ip))   ?? ""
    }
}

struct ESPSchedule: Codable, Identifiable {
    let enabled: Int
    let hour: Int
    let minute: Int
    let days: Int
    let target: Int

    var id: String { "\(hour)-\(minute)-\(days)-\(target)-\(enabled)" }

    /// 固件 sch{i} 的格式：enabled|hour|minute|days|target
    var formValue: String { "\(enabled)|\(hour)|\(minute)|\(days)|\(target)" }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// 位图：bit0=周一 … bit6=周日；0 = 每天
    var daysText: String {
        if days == 0 { return "每天" }
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        var picked: [String] = []
        for bit in 0..<7 where (days & (1 << bit)) != 0 {
            picked.append(names[bit])
        }
        if picked.isEmpty { return "每天" }
        return "周" + picked.joined(separator: "")
    }

    var isOn: Bool { enabled != 0 }

    init(enabled: Int, hour: Int, minute: Int, days: Int, target: Int) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.days = days
        self.target = target
    }

    enum CodingKeys: String, CodingKey { case enabled, hour, minute, days, target }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Int.self, forKey: .enabled)) ?? 0
        hour    = (try? c.decode(Int.self, forKey: .hour))    ?? 0
        minute  = (try? c.decode(Int.self, forKey: .minute))  ?? 0
        days    = (try? c.decode(Int.self, forKey: .days))    ?? 0
        target  = (try? c.decode(Int.self, forKey: .target))  ?? -1
    }
}

struct ESPConfig: Codable {
    let ssid: String
    let port: Int
    let count: Int
    let logac: Int          // 日志每天自动清空 1/0
    let logch: Int          // 清空时刻 时
    let logcm: Int          // 清空时刻 分
    let devices: [ESPDevice]
    let schedules: [ESPSchedule]

    enum CodingKeys: String, CodingKey {
        case ssid, port, count, logac, logch, logcm, devices, schedules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ssid      = (try? c.decode(String.self, forKey: .ssid))          ?? ""
        port      = (try? c.decode(Int.self, forKey: .port))             ?? 9
        count     = (try? c.decode(Int.self, forKey: .count))            ?? 3
        logac     = (try? c.decode(Int.self, forKey: .logac))            ?? 1
        logch     = (try? c.decode(Int.self, forKey: .logch))            ?? 0
        logcm     = (try? c.decode(Int.self, forKey: .logcm))            ?? 0
        devices   = (try? c.decode([ESPDevice].self, forKey: .devices))     ?? []
        schedules = (try? c.decode([ESPSchedule].self, forKey: .schedules)) ?? []
    }

    init(ssid: String, port: Int, count: Int, logac: Int, logch: Int, logcm: Int,
         devices: [ESPDevice], schedules: [ESPSchedule]) {
        self.ssid = ssid
        self.port = port
        self.count = count
        self.logac = logac
        self.logch = logch
        self.logcm = logcm
        self.devices = devices
        self.schedules = schedules
    }

    var logAutoClear: Bool { logac != 0 }

    /// 清空时刻的 "HH:MM"
    var logClearText: String { String(format: "%02d:%02d", logch, logcm) }
}

// MARK: - GET /api/logs

struct ESPLog: Codable, Identifiable {
    let t: String       // 时间 "10-12 18:47" 或 "开机3m20s"
    let src: String     // 手动 / 定时
    let dev: String     // 目标设备名
    let mac: String
    let pk: Int         // 实际发出包数
    let ok: Int         // 1 = 发出成功

    var id: String { "\(t)|\(src)|\(dev)|\(mac)|\(pk)" }
    var succeeded: Bool { ok == 1 }

    enum CodingKeys: String, CodingKey { case t, src, dev, mac, pk, ok }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t   = (try? c.decode(String.self, forKey: .t))   ?? ""
        src = (try? c.decode(String.self, forKey: .src)) ?? ""
        dev = (try? c.decode(String.self, forKey: .dev)) ?? ""
        mac = (try? c.decode(String.self, forKey: .mac)) ?? ""
        pk  = (try? c.decode(Int.self, forKey: .pk))     ?? 0
        ok  = (try? c.decode(Int.self, forKey: .ok))     ?? 0
    }
}

struct ESPLogs: Codable {
    let total: Int
    let count: Int
    let logs: [ESPLog]

    enum CodingKeys: String, CodingKey { case total, count, logs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = (try? c.decode(Int.self, forKey: .total))    ?? 0
        count = (try? c.decode(Int.self, forKey: .count))    ?? 0
        logs  = (try? c.decode([ESPLog].self, forKey: .logs)) ?? []
    }
}

// MARK: - 通用返回

struct BasicResult: Codable {
    let ok: Bool
    let msg: String?

    enum CodingKeys: String, CodingKey { case ok, msg }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok  = (try? c.decode(Bool.self, forKey: .ok))   ?? false
        msg = try? c.decode(String.self, forKey: .msg)
    }
}

/// POST /api/wake 的返回:
/// {"ok":true,"devices":2,"rounds":3,"packets":6,"msg":"已发送 6 个魔术包 (2 台设备 × 3 轮)"}
struct WakeResult: Codable {
    let ok: Bool
    let devices: Int?
    let rounds: Int?
    let packets: Int?
    let msg: String?

    enum CodingKeys: String, CodingKey { case ok, devices, rounds, packets, msg }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok      = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        devices = try? c.decode(Int.self, forKey: .devices)
        rounds  = try? c.decode(Int.self, forKey: .rounds)
        packets = try? c.decode(Int.self, forKey: .packets)
        msg     = try? c.decode(String.self, forKey: .msg)
    }
}
