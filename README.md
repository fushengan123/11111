# ③ iOS 唤醒 App（ESP32 WOL 远程开机）

配套 `②源码` 那份固件的 iPhone / iPad 客户端。SwiftUI 写的，零第三方依赖，自签名装到自己手机上用。

比起在 Safari 里开网页，这个 App 干的事很直接：把「全部唤醒」放在首屏最显眼的地方，单台唤醒一排按钮，唤醒记录和设备状态直接拉 `/api/*`，不用每次输密码。

---

## 功能

| 模块 | 说明 |
|------|------|
| 登录 | 账号 + 密码登录页（密码存钥匙串）；内置账号密码，首次启动自动登录，也可「退出登录」重输 |
| 服务器 | 服务器地址内置且**不在界面上显示**，用户只看到「内置服务器 · 已连接」 |
| 连接测试 | 设置里一键测当前连接 + 延迟 ms，离线时明确提示「连不上服务器」还是「账号或密码不对」 |
| 状态环 | 圆环按 RSSI 填充（-100dBm 见底 / -40dBm 满格），环里是 wifi 图标，离线变斜杠 |
| 设备状态 | 在线/离线指示灯、ESP32 当前 IP、固件版本、设备端时间，右上角标出「当前走哪条线 + 延迟」 |
| 全部唤醒 | 首屏主按钮，渐变底 + 按压回弹，发送中进度圈 + 外发光呼吸环，结果里带「经局域网 / 经外网」 |
| 单台唤醒 | 每台一张卡：名称 / MAC / 指定 IP，独立按钮独立状态，避免连点 |
| 开机状态 | 每台卡上实时显示「已开机 / 已关机 / 未上报」（来自 Win 端每 60 秒的心跳） |
| 远程关机 | 在线设备可一键关机（5 秒倒计时，Win 端执行 `shutdown /s /t 5`，可 `shutdown /a` 撤销） |
| 最近一次 | 状态卡下方一条，显示最近一条记录的成败、时间、设备、包数 |
| 唤醒记录 | 拉 `/api/logs`，来源徽标（手动 / 定时）、包数、成败、时间；支持清空（弹窗二次确认） |
| 设置 | 账号信息 / 测试连接 / 退出登录、固件配置、快捷指令、对时、重启 |
| 设备管理 | 增删改设备（名称 / MAC / 指定 IP），MAC 自动校验并归一成 `AA:BB:…`，整包写回 `/api/config` |
| 定时唤醒 | 时间 + 星期位图（bit0=周一…bit6=周日，0=每天）+ 目标设备，启用/停用，最多 8 条 |
| 固件设置 | WiFi（`/api/wifi`）、UDP 端口与轮数、唤醒记录自动清空策略、恢复出厂（`/api/reset`） |
| 快捷指令 / Siri | 自定义 URL scheme，`esp32wol://wake` 一键全部唤醒，可带 `?mac=` 指定单台 |
| 自动刷新 | 在前台每 15 秒静默拉一次状态，切后台自动停 |

魔术包是 ESP32 发的，手机只负责下指令——所以手机在哪个网段都无所谓，只要手机能 HTTP 到 ESP32。外网唤醒就是把这句话的后半句变成现实，见第七节。

---

## 目录结构

```
③iOS唤醒App/
├── ESP32WOL.xcodeproj/            # 双击就能开（含共享 scheme）
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/ESP32WOL.xcscheme
├── ESP32WOL/
│   ├── ESP32WOLApp.swift          # 入口 + URL scheme 接收
│   ├── Models.swift               # /api/status /config /logs 的模型（全部容错解码）
│   ├── APIClient.swift            # HTTP 封装，Basic Auth，错误分类
│   ├── AppState.swift             # 全局状态机：参数、设备、记录、忙碌集合、提示条
│   ├── Keychain.swift             # 密码存钥匙串
│   ├── Theme.swift                # 配色、卡片样式、触感、输入框
│   ├── ContentView.swift          # 三页签外壳 + 顶部提示条 + 定时刷新
│   ├── DevicesView.swift          # 状态环 / 全部唤醒 / 最近一次 / 设备卡
│   ├── LogsView.swift             # 唤醒记录
│   ├── SettingsView.swift         # 连接参数 / 深链 / 维护 / 关于
│   ├── Info.plist                 # ATS 放行局域网 HTTP、本地网络权限、URL scheme
│   └── Assets.xcassets/           # App 图标 + 强调色 + 启动底色
├── build-ipa.sh                   # 一条命令出 ipa（macOS）
├── .github/workflows/build-ipa.yml # 没有 Mac 就走这个：GitHub Actions 出 ipa
├── .gitignore
└── README.md                      # 本文件
```

最低系统：**iOS 16.0**。当前版本 **1.4 (build 5)**。开发环境：**Xcode 15 或更高**（Xcode 14 也能编，图标会少一条 1024 单尺寸告警）。

---

## 一、打 ipa 并装到手机上

iOS 装 App 必须签名。第一步先用下面任一方式出 `.ipa`，第二步按路线 A/B/C 签进手机。

### 出 ipa · 方式 1：有 Mac，一条命令

```bash
cd ③iOS唤醒App
chmod +x build-ipa.sh
./build-ipa.sh                        # → build/ESP32WOL-unsigned.ipa
SIGN_TEAM=ABCDE12345 ./build-ipa.sh   # → build/ESP32WOL.ipa（已签好，可直接装）
BUNDLE_ID=com.you.esp32wol ./build-ipa.sh   # 顺手改 bundle id
```

脚本干的活：`xcodebuild archive`（Release / iphoneos）→ 剥 `_CodeSignature` → 塞进 `Payload/` → `zip` 成 ipa → 打大小和 sha256。日志在 `build/archive.log`，编不过就去尾部 40 行看原因。
Team ID 在 Xcode → Settings → Accounts → 选中账号后右侧那串 10 位大写字母数字。

### 出 ipa · 方式 2：没有 Mac，走 GitHub Actions

Windows 上不可能编 iOS——没有 iOS SDK，也没有 Swift 的 SwiftUI 模块。免费的路是让 GitHub 的 macOS runner 编：

```bash
cd ③iOS唤醒App
git init && git add . && git commit -m "ESP32 WOL iOS app"
git branch -M main
git remote add origin https://github.com/你的账号/esp32wol-ios.git
git push -u origin main
```

推上去之后：**推 main 就自动开始编**（也可以在仓库页 → Actions → `build-ipa` → Run workflow 手动触发）。跑完 3～6 分钟，在本次运行页面底部 **Artifacts** 里下 `ESP32WOL-ipa`，解压就是 `ESP32WOL-unsigned.ipa`。

- 走的是 `macos-15` + Xcode 16，不签名，产物丢给 Sideloadly / AltStore 重签
- 编译日志另外存一份 `build-log` artifact（保留 14 天）
- **编挂了会自动开一个 issue**，标题 `build failed: <run_id>`，正文贴着 `error:` 行和日志尾部——照着那个改就行，不用去翻 Actions 页
- 私有仓库每月 2000 分钟免费额度，一次跑约 3 分钟

顺手一提：CI 跑之前会先跑 `tools/make-icon.py` 生成 1024 图标。仓库里不放二进制，图标由这段数学现算，每次结果一模一样（md5 恒定）。

### 路线 A：Xcode + 免费 Apple ID（最省事，7 天有效）

1. 把整个 `③iOS唤醒App` 文件夹拷到 Mac 上（U 盘 / 共享盘 / 你自己的隧道都行）
2. 双击 `ESP32WOL.xcodeproj`
3. Xcode 左侧点项目名 `ESP32WOL` → **TARGETS → ESP32WOL** → **Signing & Capabilities**
   - 勾 **Automatically manage signing**
   - **Team** 选你的 Apple ID（没有就点 Add an Account 登录，免费账号也能签）
   - **Bundle Identifier** 改成一个没人用过的，比如 `com.你的名字.esp32wol`
     （默认 `com.rna.esp32wol`，同一台设备装第二个副本会冲突）
4. 手机用数据线连 Mac，手机上「信任此电脑」
5. Xcode 顶部设备下拉选你的 iPhone → 按 **⌘R**
6. 首次运行手机会提示「不受信任的开发者」：设置 → 通用 → VPN 与设备管理 → 点你的 Apple ID → **信任**
7. 手机首次打开 App 会弹「允许访问本地网络」→ **必须允许**，否则连不上 ESP32

> 免费账号签的包 **7 天后失效**，App 打不开。到期前用 Xcode 再 ⌘R 一次就续上了（配置不会丢，Keychain 里的密码也在）。

### 路线 B：Xcode 打包 ipa + Sideloadly（Windows 装，需一台 Mac 出包）

1. Mac 上按路线 A 配好 Team
2. 菜单 **Product → Archive** → 结束后 Organizer 里点 **Distribute App → Debugging → Export**
3. 得到 `ESP32WOL.ipa`
4. Windows 上装 [Sideloadly](https://sideloadly.io/)，手机插上，把 ipa 拖进去，填 Apple ID，Start
5. 手机上同样去「VPN 与设备管理」里信任，再去「隐私与安全性 → 开发者模式」打开（iOS 16+ 需要）

### 路线 C：AltStore（手机上自动续签，7 天一次不用连电脑）

AltStore / SideStore 装好后把 ipa 丢给它，它会在同 WiFi 下自动帮你重签，到期自动续。适合长期当「开电脑按钮」用。

> 走哪条路都一样：**Bundle ID 必须是唯一的**，一个 Apple ID 免费签名同时最多 3 个 App、10 个 App ID。

---

## 二、首次使用

1. 装好打开——内置账号密码会自动登录，直接进「设备」页
2. 状态卡变绿说明服务器通了（`已连接 · 4x ms`）
3. **第一件事：加设备**。设置 → 固件配置 → 设备管理 → 添加设备（名称 + 电脑网卡的 MAC）
4. 回设备页点「全部唤醒」试一发
5. 想换账号：设置 → 退出登录 → 登录页重输（会先打到服务器验一次，错了直接告诉你）

> 注意：固件里现在的设备列表是空的（`/api/config` 返回 `devices: []`），不加设备的话「全部唤醒」会提示没有可唤醒的设备。

### 内置服务器与账号

服务器地址写死在 `ESP32WOL/AppConfig.swift`，界面上不显示、也不给改：

```swift
static let serverHosts = [
    "http://f8888.picp.vip:49999",        // 隧道域名
    "http://112.234.192.135:49999"        // 同一台服务器的 IP 直连（绕开 DNS）
]
static let serverLabel     = "内置服务器"                     // 界面上的说法
static let defaultUser     = "admin"
static let defaultPassword = "fushengan"                     // 留空则每次都要手动登录
```

- 首次启动用这组账号密码**自动登录**，直接进主界面
- 设置 → 退出登录 之后才会看到登录页（账号密码已预填，一键进）
- 换服务器 / 换账号：改这几行重编一次

## 三、快捷指令 / Siri

App 注册了 URL scheme `esp32wol`：

| 深链 | 效果 |
|------|------|
| `esp32wol://wake` | 唤醒全部已保存设备 |
| `esp32wol://wake?mac=AA:BB:CC:DD:EE:FF` | 只唤醒这一台（IP 用固件里存的） |
| `esp32wol://wake?mac=AA:BB:CC:DD:EE:FF&ip=192.168.31.50` | 指定 IP 发 |

配置方法：快捷指令 App → 新建 → 加「**打开 URL**」动作 → 粘贴上面任意一条 → 命名成「开电脑」→ 长按「添加到 Siri」，录一句「嘿 Siri，开电脑」。

> 和 `SHORTCUTS.md` 里那套「获取 URL 内容 + Basic 头」的写法并存，两种都能用。深链的好处是不用在快捷指令里存明文密码，也不用自己算 base64。

---

## 四、对接的固件接口

App 只调这几个，全部带 HTTP Basic 认证头（`Authorization: Basic base64(user:pass)`）：

| 方法 | 路径 | App 里用在哪 |
|------|------|--------------|
| GET | `/api/status` | 状态卡：`sta` / `ip` / `rssi` / `fw` / `time` |
| GET | `/api/config` | 设备列表、`count`（轮数）、`port` |
| POST | `/api/wake` | 全部唤醒（无参数） |
| POST | `/api/wake?mac=&ip=` | 单台唤醒 |
| GET | `/api/logs` | 记录页：`total` + `logs[]`（`t/src/dev/mac/pk/ok`） |
| POST | `/api/logs/clear` | 清空记录 |
| POST | `/api/time/sync` | 设置页「重新对时」 |
| POST | `/api/reboot` | 设置页「重启 ESP32」 |
| GET | `/api/pcstate` | 各电脑在线状态（`items[]: mac/on/age/cmd`） |
| POST | `/api/pcstate` | Win 端心跳（`mac` `up=1/0`），90 秒内有效 |
| POST | `/api/pccmd` | 下发关机/重启（`mac` `cmd=shutdown\|reboot\|cancel`） |
| GET | `/api/pccmd` | Win 端领命令（超过 120 秒作废） |
| POST | `/api/pccmd/ack` | Win 端执行后回执，清除命令 |

`ok:1` 只代表魔术包发出去了，电脑真开机还取决于 BIOS / 网卡 WOL 设置——这点和固件 README 一致。

---

## 五、服务器与网络（不再有内网/外网两个地址）

App 只认一个内置入口（`AppConfig.serverHost`），走的是你那条隧道 `f8888.picp.vip:49999`——实测该端口已经映射到 ESP32 的 80，手机用 4G 也能直接连，不需要和 ESP32 在同一 WiFi。

也就是说：

- **没有局域网地址了**，不用切网、不用填 IP、不依赖 mDNS
- 手机在任何网络下都走同一条路，行为一致
- 隧道断了 App 就连不上（此时固件本身也可能离线），本地网页仍可用 `http://192.168.31.231` 直接访问

隧道那头要保证的只有一件事：`f8888.picp.vip:49999` → `192.168.31.231:80` 这条映射活着。隧道面板上断开/没启动，App 会显示「连不上服务器」。

## 六、常见问题

| 现象 | 原因 / 处理 |
|------|------------|
| 一直「离线」，测试连接超时 | 两条线都不通；先用手机浏览器直接访问地址看固件网页开不开；或本地网络权限被拒（设置 → 隐私与安全性 → 本地网络 → 打开本 App） |
| 一直提示「连不上服务器」 | 隧道映射断了 / ESP32 离线 / 手机网络屏蔽非标端口；先用手机浏览器开 `http://f8888.picp.vip:49999/api/status`，返回「需要登录」说明通 |
| 在家反而要点两下才亮 | 自动模式先试局域网 2.2 秒；如果 ESP32 换了 IP，局域网这条会白等——把地址改成当前 IP，或在路由器绑静态 IP |
| 弹 401 | 用户名/密码不对；密码里带了空格；或者固件那边还没设过访问密码 |
| `esp32-wol.local` 连不上 | 部分路由器关了 mDNS 转发；直接填 IP 最稳，并在路由器里给 ESP32 绑定静态 IP |
| 设备列表空但状态是在线 | `/api/config` 里 `devices` 为空——固件网页里还没添加设备，先加一台保存 |
| 唤醒返回成功但电脑没醒 | 见固件 README 第二节：BIOS 开 WOL、网卡电源管理、关快速启动、必须有线网卡 |
| 装完 7 天后打不开 | 免费证书过期，Xcode 重新 ⌘R 或 AltStore 续签 |
| Xcode 报 bundle id 冲突 | Signing 里把 `com.rna.esp32wol` 改成你自己域名反写 |
| 打包提示 App Icon 缺失 | 只有 1024 单尺寸时 Xcode 14 会告警，不影响装；升级到 Xcode 15 就没了 |

---

## 七、想改的地方

| 想改什么 | 改哪 |
|----------|------|
| App 名字（桌面显示） | `Info.plist` → `CFBundleDisplayName` |
| 主题色 | `Theme.swift` → `Palette`；`Assets.xcassets/AccentColor` |
| 默认地址 | `AppState.swift` 里 `host = d.string(...) ?? "esp32-wol.local"` |
| 自动刷新间隔 | `ContentView.swift` 里 `Timer.publish(every: 15, ...)` |
| 加「定时唤醒」编辑 | 固件已有 `POST /api/config` 的 `sch0..schN`，模型 `ESPSchedule` 已经解好了，只缺界面 |
