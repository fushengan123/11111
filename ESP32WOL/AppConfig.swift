//
//  AppConfig.swift
//  内置默认值 —— 改这里就能改「开箱即用」的行为，不用动别的文件
//

import Foundation

enum AppConfig {

    // MARK: - 内置地址（首次启动写进设置，之后以用户改成什么为准）

    /// 局域网地址：填 IP 或 mDNS 名
    static let defaultLanHost = "esp32-wol.local"

    /// 外网地址：隧道域名 / 公网 IP:端口 / Tailscale 的 100.x.x.x
    /// ⚠️ 换成你自己的隧道地址，例如 f8888.picp.vip:49998
    static let defaultWanHost = "f8888.picp.vip:49998"

    /// 首次启动填的用户名
    static let defaultUser = "admin"

    /// 首次启动填的密码（留空就等你在设置里输；固件那边设过密码就填这儿，省一步）
    static let defaultPassword = ""

    // MARK: - 线路参数

    /// 局域网超时：短一点，跑不通立刻切外网
    static let lanTimeout: TimeInterval = 2.2

    /// 外网超时：隧道慢，给宽
    static let wanTimeout: TimeInterval = 7.0

    /// 局域网失败后静默多久不再试
    static let lanCooldown: TimeInterval = 60

    /// 前台自动刷新间隔（秒）
    static let refreshInterval: TimeInterval = 15

    // MARK: - 固件能力上限（和 ②源码 里的 MAX_DEVICES / MAX_SCHEDULES 对齐）

    static let maxDevices = 8
    static let maxSchedules = 8
}
