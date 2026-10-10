# WatchSignal / 手表离开锁屏

[中文](#中文说明) · [English](#english-guide)

## 中文说明

个人使用的 macOS 原生工具：跟踪你选定的 Apple Watch 蓝牙 RSSI，完成两步校准后，在判定离开工位时立即请求系统休眠。**Apple Watch 不需要安装应用。**

当前版本：0.3.0。前一个诊断版的校准、信号图表和 CSV 导出继续保留。

## 安装与分享

当前发布包适用于 **Apple silicon（M 系列）Mac，macOS 14 及以上**；不支持 Intel Mac。使用者不需要安装 Xcode，也不需要给手表安装应用。

从本仓库 [Releases](https://github.com/fj010434-sun/Mac_lock_when_leave/releases) 下载 ZIP，解压后将 `WatchSignal.app` 拖入“应用程序”。这是本地 ad-hoc 签名、未经 Apple 公证的个人工具。首次打开可能被 macOS 拦截；确认来源可信后，按 [Apple 官方说明](https://support.apple.com/en-us/102445)在“系统设置 → 隐私与安全性”选择“仍要打开”。

分享给朋友时，发送整个 `.app` 的 ZIP 和本说明即可。每位使用者应选择自己的手表并重新校准。应用包不包含你的手表绑定、校准或 CSV。Finder 显示的应用包修改时间可能没有随内部程序更新；版本可通过应用包内 `Contents/Info.plist` 确认。

## 从源码构建和运行

macOS 14+，Swift 6 工具链及 Command Line Tools；无第三方依赖。本机用 Swift 6.4、macOS 27.0.1 验证。

```sh
swift run --build-system native DiagnosticsTests
bash scripts/build-app.sh
open dist/WatchSignal.app
```

`dist/WatchSignal.app` 可双击运行。本地 ad-hoc 签名用于个人使用，没有 Developer ID 公证或 App Store 发布；重新构建后系统可能要求重新授权。Swift 6.4 对 `--build-system native` 有弃用警告，本机仍可用。

## 第一次使用

1. 点击“开始扫描”，允许蓝牙访问。
2. 将自己的手表靠近、移远，观察候选设备信号是否同步变化。在左侧选中设备，点击“确认这是我的手表”。不要只凭名称选择。
3. 完成下面的两步校准。若之前已保存有效校准，可以继续使用或重新采集。
4. 点击“立即休眠（测试）”，确认 Mac 进入系统睡眠，再按键或点触控板唤醒。
5. 打开“自动休眠”，回到工位，等界面显示“在工位附近”和“检测已生效”。然后测试离开、返回。

系统休眠不需要辅助功能权限；旧版本的该授权可以保留，当前版本不会发送锁屏快捷键。

每次重启应用都需手动开始扫描和打开自动休眠。应用不读取登录密码、不注册开机启动、不执行自动解锁。

## 两步校准

- 点击“1 采集工位信号”，保持常用坐姿，采集 20 秒。
- 完成后点击“2 采集离开信号”，带着手表走到希望休眠的位置，尽快站定，等满 20 秒。
- 每组至少需 10 个有效样本，工位与离开中位数相差至少 10 dB；不足时明确报错，不生成有效校准。
- 离开阈值为近远中位数的中点；返回阈值比离开阈值高 6 dB。校准结果保存，可随环境变化重新采集。
- 校准期间暂停离开休眠判断。完成后需回到工位建立新的在场起点；这时界面明确提示“尚未生效”，不会将离开位置的校准样本直接当成一次自动休眠。
- 更换目标设备时清除原设备校准并关闭自动休眠。

## 何时休眠

仅处理所选 UUID 的有效 RSSI，用 EMA 平滑（新样本权重 0.25）。先收到至少 5 个有效目标样本且平滑信号达到返回阈值，建立在场起点。

- 平滑信号连续低于离开阈值 **8 秒**，判定离开，并在同一次回调/计时器处理中直接请求休眠。
- 最后目标样本超过 5 秒显示过期；已建立在场起点后，**20 秒**无信号判定失联并请求休眠。
- 8 秒、20 秒是判定本身的防抖条件，判定成立之后没有额外休眠倒计时。计时器每秒检查一次。
- 同一次离开只请求一次；信号达到返回阈值持续 3 秒后确认返回，下一次离开可再次请求。20 秒以上的采样中断后恢复时需要重新建立在场起点。
- 暂停扫描、蓝牙不可用、系统睡眠期间不请求自动休眠。恢复/唤醒后重新建立在场起点。
- 关闭自动休眠仍可采集、分析信号；重新打开会丢弃旧判定，不补执行历史休眠事件。
- 休眠命令启动或执行失败时关闭自动休眠并显示错误，避免静默失效或反复请求。

系统执行层直接启动 `/usr/bin/pmset sleepnow` 请求整个 Mac 休眠，不发送 Control–Command–Q，也不执行仅关闭显示器的 `displaysleepnow`。命令异步执行，不阻塞主界面；启动失败或退出码非零时记录错误并关闭自动休眠。请求或退出成功不等于已确认系统睡眠。应用不更改系统电源或密码设置。

回来需要按键或点触控板唤醒，由 macOS 尝试 Apple Watch 解锁。系统休眠期间本应用无法持续采集 RSSI，也不会自行唤醒 Mac。唤醒后扫描恢复，需重新建立在场起点，再判断下一次离开。手动测试与自动离开使用同一休眠动作。睡眠期间后台任务可能暂停。


Apple Watch 解锁是否成功仍需实机验证；系统要求密码时，本应用不会绕过。确认系统已启用 Apple Watch 解锁，并使用合适的睡眠后密码策略。

## 设备识别和数据

绑定由用户确认的 UUID；其他手表不会替代目标。UUID 是 macOS 为蓝牙设备分配的标识，不是序列号或所有权证明。重置、重新配对或地址变化后可能需重新选择。RSSI 能判断信号变化，不能精确换算距离；手表熄屏后是否持续广播需实机验证，信号丢失也不一定表示人离开。

设备名称、UUID 和校准保存在 `~/Library/Application Support/WatchSignal/selection.json`。CSV 仅主动导出到本地，不上传。

图表保留最近 120 秒；离开判定和动作请求列表各最多 500 项，界面显示最近 8 个请求。CSV 记录本次会话最近 50,000 行，截断会显示计数。

- 顶部是当前校准摘要；逐行保留当时的校准版本、阈值和样本数。
- `departure` 行表示检测器判定离开，自动休眠关闭时也可能出现。
- `lockRequest` 行表示一次动作执行尝试（保留旧版行名）；`event_reason` 为 `weakSignal`、`missingSignal` 或手动测试 `manual`。
- `lock_result=requested` 表示休眠命令已启动（`detail` 标记 `systemSleep`）；`failed` 表示请求失败，原因写入 `detail`。它们均不是系统实际休眠的确认回执。
- `systemSleepRequest` 单独记录系统休眠命令退出结果；`requested` 表示退出码为零，`failed` 表示命令失败。旧版本 `displaySleepRequest` 记录仍可识别。
- 日志未逐次记录每次定时器状态或扫描暂停、恢复；分析信号空档时需结合实际操作时间。

## 验证范围

自动测试通过独立 Swift 可执行程序运行（本机 CLT 没有 XCTest）：可按测试名包含的字符串筛选，未提供参数运行全部；断言失败或筛选不到测试返回非零退出码。

测试验证近远校准、单目标隔离、EMA、防抖/失联边界、暂停/睡眠恢复、参数保存/CSV，以及离开判定同次调用执行动作、一次离开仅执行一次、返回后重触发、命令失败和错误记录。旧版锁屏权限行为仍有回归测试。测试替换休眠副作用；实际进程测试仅运行无副作用的命令，不会让测试机器休眠。

戴表实机验收：先确认“立即休眠”按钮有效，再开启自动休眠并等“检测已生效”，离开 30 秒、返回 10 秒，重复 5 次并记录时刻。还需检查坐在桌前和手表熄屏时是否误休眠；自动测试不证明蓝牙广播稳定或系统休眠实际成功。

历史诊断设计及验证记录保存在 `docs/`；当前使用行为以本 README 为准。

参考：[Apple Watch 解锁 Mac](https://support.apple.com/en-us/102442)；系统休眠命令依据本机 `man pmset` 的 `sleepnow` 说明。

---

## English guide

WatchSignal is a personal macOS utility that monitors the Bluetooth RSSI of the Apple Watch you select. After two-step calibration, it requests **system sleep as soon as departure is confirmed**. No app needs to be installed on the watch.

Current version: **0.3.0 (build 4)**. Calibration, signal charts and CSV export remain available. The app UI currently uses Chinese; the button labels below match that UI.

### Install and share

- The current release supports **Apple silicon (M-series) Macs running macOS 14 or later**. Intel Macs are not supported by this binary. Xcode is not required to run it.
- Download the ZIP from [Releases](https://github.com/fj010434-sun/Mac_lock_when_leave/releases), extract it and move `WatchSignal.app` to Applications.
- This personal build is ad-hoc signed and has not been notarized by Apple. macOS may block the first launch. If you trust its source, follow [Apple’s instructions](https://support.apple.com/en-us/102445) to open it through System Settings → Privacy & Security → Open Anyway.
- To share it, send the ZIP containing the complete `.app` and this guide. Each person must select their own watch and calibrate it. The app bundle does not contain your watch selection, calibration or exported CSV files.
- Finder may show an older modification time for the outer `.app` directory even when its internal executable has been updated. The version is recorded in `Contents/Info.plist` inside the bundle.

### First use

1. Click **开始扫描** (Start scanning) and allow Bluetooth access.
2. Move your watch closer and farther away, checking which device’s signal follows the movement. Select it and click **确认这是我的手表** (Confirm this is my watch). Do not rely only on the device name.
3. Complete the two calibration steps below. Valid calibration saved on this Mac can be reused or replaced.
4. Click **立即休眠（测试）** (Sleep now — test). Confirm that the Mac sleeps, then press a key or use the trackpad to wake it.
5. Enable **自动休眠** (Automatic sleep). Stay at your desk until the app shows **在工位附近** (Near the desk) and **检测已生效** (Detection active). Then test leaving and returning.

System sleep does not require Accessibility permission. The current app does not send the lock-screen keyboard shortcut. After each app restart, start scanning and enable automatic sleep again. The app does not read your login password, start automatically at login, or perform automatic unlocking.

### Two-step calibration

- Click **1 采集工位信号** (Collect desk signal). Remain in your normal seated position for 20 seconds.
- Click **2 采集离开信号** (Collect away signal). Move to the position where you want sleep to trigger, stand still promptly, and wait for the 20-second collection to finish.
- Each step needs at least 10 valid samples. The desk and away medians must differ by at least 10 dB. Otherwise, calibration fails with an error.
- The departure threshold is the midpoint of the two medians. The return threshold is 6 dB higher. Calibration is saved locally and can be repeated when your environment changes.
- Departure detection is suspended during calibration. Afterwards, return to your desk to establish a fresh presence baseline. Calibration samples taken away from the desk do not immediately trigger sleep.
- Selecting a different device clears the previous calibration and turns automatic sleep off.

### When sleep is requested

Only valid RSSI samples from the selected UUID are processed. An exponential moving average uses a weight of 0.25 for new samples. At least five fresh valid samples and a smoothed signal at or above the return threshold are needed to establish presence.

- A smoothed signal continuously below the departure threshold for **8 seconds** confirms departure.
- After presence has been established, **20 seconds without a target sample** confirms signal loss and requests sleep. Samples older than five seconds are shown as stale.
- These intervals are detection debounce conditions. There is no additional countdown after departure is confirmed. The timer checks once per second.
- One departure generates one action. A signal at or above the return threshold for three seconds confirms return. A sampling gap of 20 seconds or longer requires a fresh presence baseline.
- Pausing scanning, unavailable Bluetooth and system sleep suspend automatic actions. Resuming or waking requires a fresh baseline.
- Turning automatic sleep off still permits data collection. Turning it back on does not replay previous departure events.
- A command launch failure or a nonzero exit status is logged, displayed and turns automatic sleep off.

The production action starts `/usr/bin/pmset sleepnow` asynchronously to request **whole-system sleep**. It does not send Control–Command–Q or use display-only sleep. A launched command or successful exit is not an acknowledgement that the Mac actually slept. The app does not change power-management or password settings. Background work may pause while the Mac sleeps.

When you return, press a key or use the trackpad to wake the Mac. macOS then attempts Apple Watch unlocking if you have enabled that feature. WatchSignal cannot continuously collect RSSI while the Mac sleeps and does not wake it automatically. Scanning resumes on wake and establishes a fresh baseline for the next departure. The manual test uses the same sleep action.

Apple Watch unlocking must be verified on the actual devices. If macOS requires a password, the app does not bypass it. Configure Apple Watch unlocking and an appropriate password requirement after sleep in macOS. See [Apple’s guide](https://support.apple.com/en-us/102442).

### Device identity and local data

The app tracks only the UUID you confirm; another watch cannot replace it automatically. The UUID is assigned by macOS and is not a serial number or proof of ownership. Resetting or pairing a device again, or an address change, may require selecting it again. RSSI indicates signal changes, not exact distance. Broadcast behavior when the watch display is off needs device testing; signal loss does not necessarily mean you have left.

The device name, UUID and calibration are stored at `~/Library/Application Support/WatchSignal/selection.json`. CSV is exported only when you request it and is not uploaded.

Charts retain 120 seconds of samples. Departure and action histories retain up to 500 entries each; the UI shows the latest eight action entries. CSV retains the latest 50,000 rows of the current session and reports truncation.

- The header summarizes the current calibration; each row preserves the calibration version and values used at that time.
- `departure` records a detector decision, including while automatic sleep is off.
- `lockRequest` is the retained legacy name for an action attempt. Reasons include `weakSignal`, `missingSignal` and `manual`.
- `lock_result=requested` on an action attempt means the sleep command was launched; `detail` identifies `systemSleep`. `failed` records an error. Neither confirms actual system sleep.
- `systemSleepRequest` records command completion: `requested` means exit status zero; `failed` means execution failed. Older `displaySleepRequest` records remain supported.
- Logs do not record every timer state or every scanning pause/resume. Interpret gaps alongside the times of your actual actions.

### Build and validation

Building from source requires macOS 14+, Swift 6 and Command Line Tools. There are no third-party dependencies. This build was checked with Swift 6.4 on macOS 27.0.1.

```sh
swift run --build-system native DiagnosticsTests
bash scripts/build-app.sh
open dist/WatchSignal.app
```

Swift 6.4 warns that `--build-system native` is deprecated; it remains usable in the tested environment. Rebuilding the ad-hoc signed app may cause macOS to request permissions again.

The independent Swift test executable supports filtering by a substring of the test name and returns a nonzero status for failures or no matches. Version 0.3.0 passed 40 tests covering calibration, selected-device isolation, smoothing and debounce boundaries, signal loss, pause/wake behavior, persistence, CSV, departure actions, command errors and legacy lock behavior. Sleep side effects are substituted; actual process tests use harmless commands and do not put the test machine to sleep.

For device acceptance, test Sleep now, enable automatic sleep, wait for Detection active, leave for 30 seconds and return for 10 seconds. Repeat five times and note the times. Also check for unwanted sleep while seated and while the watch display is off. Automated tests do not prove reliable Bluetooth broadcasting, actual system sleep or successful Watch unlocking.

Historical design and verification records are in `docs/`. This README describes the current behavior. The command behavior is documented by the local `man pmset` entry for `sleepnow`.
