//
//  AppConfig.swift
//  内置服务器与各项参数 —— 地址全部隐藏，界面上不出现
//

import Foundation

enum AppConfig {

    // MARK: - 内置服务器（外网隧道，界面不显示也不可改）

    /// 入口列表，按顺序试；第一条失败（DNS/超时）自动换下一条。
    /// 第二条是同一台服务器的 IP 直连，绕开 DNS。
    static let serverHosts = [
        "http://f8888.picp.vip:49999",
        "http://112.234.192.135:49999"
    ]

    /// 界面上仍然只用一个名字
    static var serverHost: String { serverHosts[0] }

    /// 界面上对外的说法（不暴露真实地址）
    static let serverLabel = "内置服务器"

    /// 登录默认用户名（用户可改）
    static let defaultUser = "admin"

    /// 登录默认密码：填了就能免登录直接进主界面；清空则每次都要输
    static let defaultPassword = "fushengan"

    // MARK: - 请求参数

    static let requestTimeout: TimeInterval = 12
    static let wakeTimeout: TimeInterval = 15
    static let refreshInterval: TimeInterval = 15

    /// 电脑端关机缓冲秒数（与 wolboot.ini 的 delay 对应）
    static let shutdownDelay = 30

    // MARK: - 固件能力上限（对齐 ②源码 的 MAX_DEVICES / MAX_SCHEDULES）

    static let maxDevices = 8
    static let maxSchedules = 8
}
