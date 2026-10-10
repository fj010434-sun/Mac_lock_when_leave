# 指定 Apple Watch RSSI 诊断工具 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付用户可在本机启动的诊断应用，绑定手动确认的设备、显示 RSSI 曲线并模拟离开锁屏判断。

**Architecture:** 无第三方依赖的 Swift Package 包含纯逻辑 `WatchSignalCore`、平台适配 `WatchSignalPlatform` 和可执行目标 `WatchSignalApp`。平台层负责蓝牙、持久化和系统生命周期，界面共用一个诊断模型；脚本将可执行文件打包为本地 `.app`。

**Tech Stack:** Swift 6.4、Swift Package Manager、XCTest、AppKit、SwiftUI、Core Bluetooth、Swift Charts、macOS SDK、codesign。

**Spec:** `docs/superpowers/specs/2026-10-10-watch-rssi-diagnostic-design.md`

## Global Constraints

- 部署目标 macOS 14.0；无第三方依赖。
- 当前阶段交付可运行的诊断 `.app`，显示“此刻会锁屏”，不执行锁屏。
- 当前不建立 Watch App。
- 不在初版主动连接手表，不发送 GATT 写入指令。
- 监测、曲线、校准和判定只消费选定 UUID 的样本；其他设备不参与。
- 不得用相同名称、厂商或最接近的 RSSI 自动绑定其他 UUID。
- 不保存 Mac 登录密码。
- 代码测试和构建成功均不等于上述实机条件成立。

## Review Focus

- 附近同名设备、UUID 不同：不能代替目标，也不能参与校准和信号丢失计时。
- 稀疏广播或样本停止：时钟刷新不能制造新样本，失去新鲜度即取消弱信号连续计时。
- 睡眠、权限改变和蓝牙关闭：不能将系统暂停时间计入离开；恢复须重新建立在场起点。
- 手表身份变化或重启应用：保留选择但显示等待目标信号，不能凭保存的 EMA 自动判定。
- 重新校准或换设备：旧阈值和计时不能污染新会话；失败的校准不能变成有效配置。

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `Package.swift` | 三个目标及核心、平台测试目标，macOS 14 |
| `Sources/WatchSignalCore/SignalTypes.swift` | 样本、校准、状态、模拟事件、配置类型 |
| `Sources/WatchSignalCore/Calibration.swift` | 20 秒采集窗口、中位数和校准验证 |
| `Sources/WatchSignalCore/PresenceDetector.swift` | UUID 过滤、EMA、迟滞和样本过期判定 |
| `Sources/WatchSignalCore/SessionLog.swift` | 本次会话记录、CSV 编码 |
| `Sources/WatchSignalPlatform/BluetoothScanner.swift` | Core Bluetooth 被动重复扫描 |
| `Sources/WatchSignalPlatform/SelectionStore.swift` | 所选 UUID、名称和校准持久化 |
| `Sources/WatchSignalPlatform/DiagnosticModel.swift` | 单一选择来源、时钟、校准、日志和生命周期 |
| `Sources/WatchSignalApp/WatchSignalApp.swift` | 应用入口、菜单栏入口和诊断窗口 |
| `Sources/WatchSignalApp/DiagnosticView.swift` | 设备选择、身份、信号图、状态、校准和导出 |
| `Tests/WatchSignalCoreTests/CalibrationTests.swift` | 校准数据契约 |
| `Tests/WatchSignalCoreTests/PresenceDetectorTests.swift` | 判定边界和目标隔离 |
| `Tests/WatchSignalCoreTests/SessionLogTests.swift` | 导出内容和 CSV 转义 |
| `Tests/WatchSignalPlatformTests/DiagnosticModelTests.swift` | 可替换扫描器、存储、时钟的模型测试 |
| `scripts/build-app.sh` | release 构建、Info.plist、签名、产物 |
| `README.md` | 启动、设备确认、校准和实机验证步骤 |
| `.gitignore` | 忽略 `.build/`、`dist/`、本地日志和 `.DS_Store` |

## Task 1: 核心校准、判定与会话日志

**Files:** 创建 Package.swift、核心四个文件、核心测试三个文件和 .gitignore；为后续包目标建立最小可编译占位入口，不引入蓝牙行为。

**Interfaces:**

- `SignalSample(deviceID: UUID, timestamp: Date, rssi: Int)`；`Calibration(nearMedian: Double, farMedian: Double, nearCount: Int, farCount: Int, createdAt: Date)`；`awayThreshold` 和 `returnThreshold` 为只读属性。
- `CalibrationCollector.init(deviceID: UUID)`、`start(phase: CalibrationPhase, at: Date)`、`ingest(_ sample: SignalSample)`、`finish(at: Date) throws -> Calibration?`；phase 为 near/far；仅接收目标 UUID；首组完成返回 nil，第二组完成返回校准。错误需区分时间不足、样本不足与区分不足。
- `PresenceDetector.init(deviceID: UUID, calibration: Calibration?)`、`ingest(_ sample: SignalSample)`、`tick(at: Date)`、`reset()`、`setCalibration(_ calibration: Calibration?)`；提供只读 `snapshot: PresenceSnapshot` 和 `events: [SimulationEvent]`。
- `PresenceState` 含 uncalibrated/warmingUp/present/pendingAway/awayWeak/stale/awayMissing/pendingReturn/returned；snapshot 提供 EMA、目标最后采样时间及状态。系统暂停由平台停止 tick 并 reset。
- `SessionLog.append(sample: SignalSample, snapshot: PresenceSnapshot)`、`append(event: SimulationEvent)`、`csv(deviceID: UUID, name: String, calibration: Calibration?) -> String`。选定设备样本与校准参数导出；字符串按 CSV 双引号转义、时间为 ISO 8601。

- [ ] 写 XCTest：`testCalibrationRequiresTwentySecondsAndTenSamples` 断言不足 20 秒或每组不足 10 个样本均失败；near=-45、far=-65 得到离开=-55、返回=-49；near=-45、far=-54 时失败，差值 10 时成功。
- [ ] 写目标隔离测试：设备 A 为选择，B 同时大量上报 -100；A 状态、EMA、lastSample 和校准样本数均不能受 B 影响。RSSI 127、0、-128 忽略，-127 与 -1 接受。
- [ ] 写判定测试：用可控 Date 和校准 near=-45/far=-65，先送入至少 5 个近样本建立在场；持续弱样本达到条件后 7.99 秒无事件，8 秒仅一个 awayWeak 事件；弱信号期间短暂恢复取消计时。EMA 第一值初始化原值，之后系数 0.25。
- [ ] 写迟滞测试：返回只在 EMA 达到 -49 后连续 3 秒成立，2.99 秒不成立；-55 到 -49 之间不能触发返回。每秒 tick 不生成重复模拟事件。
- [ ] 写新鲜度测试：无新样本的 5 秒边界仍新鲜，超过 5 秒 stale，取消弱信号连续计时；20 秒触发一次 awayMissing，仅已建立在场且有效校准时允许；其他设备样本不能延长该期限。丢失后首个目标新样本重置平滑和起点。
- [ ] 写 reset/setCalibration 测试：清除 EMA、样本计数、在场起点与连续计时；无校准/不足 5 样本/从未在场时无事件。重新校准后不能用旧弱信号计时立即产生事件。
- [ ] 写日志测试：只导出指定设备本次会话数据，包含校准参数、事件原因，名称中的逗号/双引号/换行能够正确转义。
- [ ] 运行 `swift test --filter WatchSignalCoreTests`，确认测试因未实现的接口或行为失败。
- [ ] 实现核心模块：时间计算使用传入 Date；校准窗口不接收结束时刻之后的样本；tick 只推进状态，不能更新 lastSample。添加有限日志缓冲（最近 50,000 条），超出时计数并在导出附注中说明截断，不宣称完整会话。
- [ ] 重跑 `swift test --filter WatchSignalCoreTests`，所有上述断言通过。
- [ ] 提交：`git add Package.swift Sources Tests .gitignore`，`git diff --cached --check`，`git commit -m "feat: add target-isolated RSSI diagnostic core"`。

## Task 2: 被动扫描与本地诊断模型

**Files:** 创建平台三个文件、平台模型测试；完善 Package.swift 平台目标依赖。

**Interfaces:**

- `@MainActor protocol SignalScanning: AnyObject` 提供 `onSample: ((SignalSample, String?) -> Void)?`、`onAvailability: ((ScannerAvailability) -> Void)?`、`start()`、`stop()`。
- `ScannerAvailability` 为 ready/unauthorized/poweredOff/unsupported/unavailable；真实扫描器仅在 ready 下启动 `scanForPeripherals(withServices:nil, options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])`；回调到达时创建 timestamp。
- `SelectionStore.load() -> SavedSelection?`、`save(_ selection: SavedSelection?) throws`；SavedSelection 包含 UUID、用户名称及可选 Calibration，使用 Codable 本地存储，初始化不保存临时 EMA。
- `@MainActor DiagnosticModel.init(scanner: any SignalScanning, store: SelectionStore, now: @escaping () -> Date)`；`select(deviceID: UUID, name: String)`、`start()`、`pause()`、`advance(at: Date)`、`beginCalibration(_ phase: CalibrationPhase)`、`handleSleep()`、`handleWake()`、`exportCSV() -> String`。
- 模型公开 `devices`、`selectedID`、`selectedName`、`snapshot`、`chartSamples`、`events`、`availability`、`isRunning`、`errorMessage`、校准阶段/进度。唯一 selectedID 是扫描样本、曲线、校准、持久化和日志过滤来源。

- [ ] 创建 FakeScanner、临时存储和可控时钟测试。断言 `testOtherDeviceCannotReplaceSelection`：两个同名设备只有 A 被选，B 回调不能替换 A、更新图表或填充校准。
- [ ] 添加 `testRestoreWaitsForFreshTarget`：保存 A 和有效校准，重新初始化仅保留选择；无新目标样本时无模拟事件。
- [ ] 添加 `testPauseAndUnavailableCancelTimers`：权限拒绝、蓝牙关闭、暂停都 stop/reset，时钟推进 60 秒无离开事件；恢复仍须重新收到样本并建立在场起点。
- [ ] 添加 `testSleepWakeNeedsNewBaseline`、`testDeviceChangeDropsCalibration`、`testExpiredSamplesArePruned`：睡眠/唤醒清空计时；换设备清空校准与旧会话；chartSamples 只保留 120 秒内目标数据。蓝牙重新 ready 不自动启动用户已暂停的会话。
- [ ] 添加 `testCalibrationFailureAndStoreFailureAreVisible`：校准失败不能持久化成有效配置；损坏配置显示错误而不崩溃；写入失败保留可见错误；重新开始校准立即暂禁旧校准判定直到完成。
- [ ] 运行 `swift test --filter DiagnosticModelTests` 确认失败后实现平台模块。使用 @MainActor 隔离界面模型，蓝牙 delegate 的 Swift 并发桥接遵循 SDK 签名；不通过关闭所有并发检查掩盖错误。
- [ ] 生命周期接入 NSWorkspace 的 sleep/wake 通知；应用终止停止扫描。每秒驱动 advance，仅用户启动且扫描 ready 时执行 detector.tick。
- [ ] 运行 `swift test`；检查 Core Bluetooth 代码只有扫描/停止调用，没有 connect、GATT 写入或自动选择操作。
- [ ] 提交：`git add Package.swift Sources/WatchSignalPlatform Tests/WatchSignalPlatformTests`，`git diff --cached --check`，`git commit -m "feat: add passive Bluetooth diagnostic session"`。

## Task 3: 原生界面、应用打包与交付

**Files:** 创建/完善应用两个文件、scripts/build-app.sh、README.md。

**Interfaces:** 界面从单个 DiagnosticModel 读取状态；导出调用 exportCSV()，通过 NSSavePanel 保存；保存失败显示 errorMessage。构建脚本产出 `dist/WatchSignal.app`，可执行文件 `WatchSignal`，bundle ID `local.sunyifeng.WatchSignal`。

- [ ] 构建中文诊断窗口：设备列表展示名称/UUID/RSSI/最后信号；点击后仍需“确认这是我的手表”按钮才调用 select；显示身份为“用户已确认”，不能根据厂商识别显示“已认证”。
- [ ] 加入开始/暂停、工位/离开两步校准、120 秒原始与 EMA 曲线、阈值参考线、信号年龄和模拟事件。清楚显示“诊断模式，不会实际锁屏”；样本不足、信号过期、权限状态和目标丢失分别显示。
- [ ] 提供菜单栏打开诊断窗口和退出；启动应用不自动扫描，不自动注册开机启动。CSV 导出显示本地保存对话框；日志截断计数可见。
- [ ] 编写打包脚本：`set -euo pipefail`、按脚本位置解析项目路径、`swift build -c release`、复制可执行文件、生成 CFBundle/LSMinimumSystemVersion/NSBluetoothAlwaysUsageDescription。应用名“手表信号诊断”，用途说明“读取你选择的蓝牙设备信号，用于验证离开工位的判断。”
- [ ] 使用 `codesign --force --sign - dist/WatchSignal.app` 本地签名；不添加辅助功能权限、密码访问或自动化权限。
- [ ] 写 README：`bash scripts/build-app.sh`、`open dist/WatchSignal.app`；说明首次蓝牙授权、确认设备、两组校准、只模拟锁屏、日志导出和 UUID 变化后重新选择。
- [ ] 执行 `swift test`、`bash scripts/build-app.sh`、`plutil -lint dist/WatchSignal.app/Contents/Info.plist`、`codesign --verify --strict --verbose=2 dist/WatchSignal.app`；全部成功才声明测试、构建和打包通过。
- [ ] 启动应用并尽量进行可用的 UI 检查：窗口可打开、按钮禁用状态、设备列表和权限提示。如果系统权限需要用户操作，保留提示并报告，不自动更改系统权限。权限授予前只能报告启动结果，不能声称已读到手表。
- [ ] 将实机验收写成 README 清单：熄屏观察 10 分钟、桌前活动 10 分钟、5 次离开返回、应用/手表重启、附近另一块表。记录样本间隔、误判与漏判；由用户确认设备身份与实际位置。
- [ ] 提交：`git add Sources/WatchSignalApp scripts/build-app.sh README.md`，`git diff --cached --check`，`git commit -m "feat: package native Watch signal diagnostic app"`。

## 执行方式与交付边界

推荐由当前助手直接在本会话执行三项任务：模块接口紧密、工程小，便于及时验证。无需用户选择模型或创建额外聊天。

执行前请用户审阅本计划并确认执行方式。用户批准后使用 executing-plans 技能实施。完成后提供 `.app` 与 README 链接，区分自动测试、构建签名、UI 检查和未完成的实机验证。当前计划不接入实际锁屏；必须先取得用户实机数据再评估下一阶段。
