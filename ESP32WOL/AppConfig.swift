//
//  AppConfig.swift
//  内置服务器与各项参数 —— 地址全部隐藏，界面上不出现
//

import Foundation

enum AppConfig {

    // MARK: - 内置服务器（外网隧道，界面不显示也不可改）

    /// 线上入口。换服务器只改这一行。
    static let serverHost = "http://f8888.picp.vip:49999"

    /// 界面上对外的说法（不暴露真实地址）
    static let serverLabel = "内置服务器"

    /// 登录默认用户名（用户可改）
    static let defaultUser = "admin"

    /// 登录默认密码：填了就能免登录直接进主界面；清空则每次都要输
    static let defaultPassword = "fushengan"

    // MARK: - 请求参数

    static let requestTimeout: TimeInterval = 8
    static let wakeTimeout: TimeInterval = 15
    static let refreshInterval: TimeInterval = 15

    // MARK: - 固件能力上限（对齐 ②源码 的 MAX_DEVICES / MAX_SCHEDULES）

    static let maxDevices = 8
    static let maxSchedules = 8
}
