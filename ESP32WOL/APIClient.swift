//
//  APIClient.swift
//  ESP32 WOL 远程开机 — 固件 HTTP 接口封装
//

import Foundation

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case http(Int, String)
    case transport(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "设备地址不合法，例如 192.168.31.231 或 esp32-wol.local:80"
        case .unauthorized:
            return "用户名或密码不对 (401)"
        case .http(let code, let body):
            let tail = body.isEmpty ? "" : " " + String(body.prefix(80))
            return "设备返回 HTTP \(code)\(tail)"
        case .transport(let m):
            return "连不上 ESP32：\(m)"
        case .decode(let m):
            return "返回内容解析失败：\(m)"
        }
    }
}

struct APIClient {
    let base: URL
    let user: String
    let pass: String
    /// 单次请求超时。局域网 2 秒够用，穿隧道给 7 秒。
    let timeout: TimeInterval

    init?(host: String, user: String, pass: String, timeout: TimeInterval = 6) {
        guard let url = APIClient.makeBaseURL(host) else { return nil }
        self.base = url
        self.user = user
        self.pass = pass
        self.timeout = timeout
    }

    /// 接受 "192.168.31.231" / "esp32-wol.local" / "http://1.2.3.4:8080" / 带结尾斜杠
    static func makeBaseURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private var authHeader: String? {
        guard !user.isEmpty else { return nil }
        let raw = "\(user):\(pass)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    private func makeRequest(_ path: String,
                             method: String = "GET",
                             query: [URLQueryItem] = [],
                             form: [String: String]? = nil,
                             timeout: TimeInterval? = nil) -> URLRequest? {
        var url = base.appendingPathComponent(path)
        if !query.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = query
            if let built = comps.url { url = built }
        }
        var req = URLRequest(url: url, timeoutInterval: timeout ?? self.timeout)
        req.httpMethod = method
        req.setValue("close", forHTTPHeaderField: "Connection")
        if let auth = authHeader {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let form = form {
            var comps = URLComponents()
            comps.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            let body = comps.percentEncodedQuery ?? ""
            req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = body.data(using: .utf8)
        }
        return req
    }

    private func send<T: Decodable>(_ type: T.Type,
                                    path: String,
                                    method: String = "GET",
                                    query: [URLQueryItem] = [],
                                    form: [String: String]? = nil,
                                    timeout: TimeInterval? = nil) async throws -> T {
        guard let req = makeRequest(path, method: method, query: query, form: form, timeout: timeout) else {
            throw APIError.badURL
        }
        var payload = Data()
        var response: URLResponse?
        do {
            let result = try await URLSession.shared.data(for: req)
            payload = result.0
            response = result.1
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("没有收到响应")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: payload, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: payload)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    // MARK: - 具体接口

    func status() async throws -> ESPStatus {
        try await send(ESPStatus.self, path: "api/status")
    }

    func config() async throws -> ESPConfig {
        try await send(ESPConfig.self, path: "api/config")
    }

    func logs() async throws -> ESPLogs {
        try await send(ESPLogs.self, path: "api/logs")
    }

    /// 不带参数 = 全部唤醒
    func wakeAll() async throws -> WakeResult {
        try await send(WakeResult.self, path: "api/wake", method: "POST", form: [:], timeout: 15)
    }

    /// 单台唤醒 (mac 必填, ip 可空 = 走广播)
    func wake(mac: String, ip: String) async throws -> WakeResult {
        var q = [URLQueryItem(name: "mac", value: mac)]
        if !ip.isEmpty { q.append(URLQueryItem(name: "ip", value: ip)) }
        return try await send(WakeResult.self, path: "api/wake",
                              method: "POST", query: q, timeout: 15)
    }

    func clearLogs() async throws -> BasicResult {
        try await send(BasicResult.self, path: "api/logs/clear", method: "POST", form: [:])
    }

    func syncTime() async throws -> BasicResult {
        try await send(BasicResult.self, path: "api/time/sync", method: "POST", form: [:])
    }

    func reboot() async throws -> BasicResult {
        try await send(BasicResult.self, path: "api/reboot", method: "POST", form: [:], timeout: 4)
    }
}
