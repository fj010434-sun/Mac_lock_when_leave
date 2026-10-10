import AppKit
import SwiftUI
private typealias ViewState<Value> = SwiftUI.State<Value>
import Charts
import WatchSignalCore
import WatchSignalPlatform
struct DiagnosticView: View {
 @ObservedObject var model: DiagnosticModel
 @ViewState private var candidate: UUID? = nil
 @ViewState private var customName="我的 Apple Watch"
 private let accent=Color(red:0.14,green:0.42,blue:0.70)
 var body: some View {
  HStack(spacing:0) {
   sidebar.frame(width:310)
   Divider()
   ScrollView {
    VStack(alignment:.leading,spacing:22) {
     header
     if let error=model.errorMessage {
      HStack(alignment:.top) {
       Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
       Text(error).font(.callout)
       Spacer()
       Button { model.errorMessage=nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain)
      }.padding(12).background(Color.orange.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
     }
     targetCard
     lockCard
     signalCard
     calibrationCard
     eventCard
     Text("信号强度用于判断近远，不能精确换算距离。设备身份由你确认；识别丢失时不会自动换成另一块手表。")
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }.padding(28)
   }.background(Color(nsColor:.windowBackgroundColor))
  }.frame(minWidth:960,minHeight:670).tint(accent)
 }
 private var sidebar: some View {
  VStack(alignment:.leading,spacing:16) {
   Label("附近设备",systemImage:"dot.radiowaves.left.and.right").font(.headline)
   Text("靠近、移远你的手表，观察信号变化后再确认。设备名称仅供参考。")
    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
   if model.devices.isEmpty {
    VStack(spacing:12) {
     Image(systemName:"applewatch.radiowaves.left.and.right").font(.system(size:34)).foregroundStyle(.secondary)
     Text(model.requestedScanning ? "等待附近蓝牙广播" : "先开始扫描").font(.headline)
     Text("尚未确认任何手表").font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth:.infinity).padding(.vertical,28)
   }
   List(selection:$candidate) {
    ForEach(model.devices.sorted { $0.rssi > $1.rssi }) { device in
     VStack(alignment:.leading,spacing:5) {
      HStack { Text(device.name).lineLimit(1);Spacer();Text("\(device.rssi) dBm").monospacedDigit().font(.caption) }
      Text(device.id.uuidString).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
      HStack {
       if model.selectedID == device.id { Label("已选定",systemImage:"checkmark.circle.fill").foregroundStyle(accent) }
       Spacer();Text("\(age(device.lastSeen)) 秒前").foregroundStyle(.secondary)
      }.font(.caption2)
     }.padding(.vertical,6).tag(device.id)
    }
   }.listStyle(.sidebar)
   VStack(alignment:.leading,spacing:10) {
    TextField("给目标设备起个名字",text:$customName).textFieldStyle(.roundedBorder)
    Button("确认这是我的手表") {
     if let candidate { model.select(deviceID:candidate,name:customName) }
    }.buttonStyle(.borderedProminent).disabled(candidate == nil || !model.isRunning || model.calibrationPhase != nil)
    Text("确认后只跟踪该 UUID。UUID 不是手表序列号。")
     .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
   }
  }.padding(18).background(Color(nsColor:.controlBackgroundColor))
 }
 private var header: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(alignment:.top) {
    VStack(alignment:.leading,spacing:6) {
     Text("手表离开锁屏").font(.system(size:28,weight:.semibold))
     Text("只跟踪你的手表，判定离开后立即锁屏").foregroundStyle(.secondary)
    }
    Spacer()
    Button(model.requestedScanning ? "暂停扫描" : "开始扫描") {
     if model.requestedScanning { model.pause() } else { model.start() }
    }.buttonStyle(.borderedProminent).controlSize(.large)
   }
   HStack(spacing:7) {
    Image(systemName:model.automaticLockEnabled ? "lock.shield" : "waveform.path")
    Text(model.automaticLockEnabled ? "自动锁屏已开启" : "自动锁屏已关闭 · 仅采集信号")
    Spacer()
    Circle().fill(model.isRunning ? Color.green : Color.gray).frame(width:7,height:7)
    Text(scannerLabel)
   }.font(.caption).foregroundStyle(.secondary)
  }
 }
 private var lockCard: some View {
  card {
   VStack(alignment:.leading,spacing:12) {
    HStack {
     Toggle("自动锁屏",isOn:Binding(get:{model.automaticLockEnabled},set:{model.setAutomaticLock($0)})).toggleStyle(.switch)
      .disabled(!model.automaticLockEnabled && (!model.isRunning || model.calibration == nil || model.calibrationPhase != nil))
     Spacer()
     Text(model.lockAuthorized ? "锁屏权限已授权" : "需要辅助功能权限").font(.caption).foregroundStyle(model.lockAuthorized ? .green : .orange)
    }
    Text(protectionLabel).font(.callout).fixedSize(horizontal:false,vertical:true)
    HStack {
     Button("授权锁屏权限") { model.requestLockAuthorization() }
     Button("立即锁屏（测试）") { model.lockNow() }.disabled(!model.lockAuthorized)
    }.buttonStyle(.bordered)
    Text("离开判定成立后直接发送系统锁屏快捷键。同一次离开只请求一次；返回不会自动解锁。")
     .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
   }
  }
 }
 private var protectionLabel: String {
  if model.calibrationPhase != nil { return "正在校准，自动锁屏暂时不生效。" }
  if model.calibration == nil { return "完成下面的两步校准，再开启自动锁屏。" }
  if !model.automaticLockEnabled { return "校准已保存。开启自动锁屏后，请回到工位等待显示“在工位附近”。" }
  if !model.isRunning { return "采集已暂停，自动锁屏暂时不生效。" }
  switch model.snapshot.state {
  case .warmingUp: return "请回到工位，等待显示“在工位附近”；当前尚未建立在场起点。"
  case .present,.returned: return "检测已生效。带着手表离开工位可触发锁屏。"
  case .pendingAway: return "信号变弱，正在确认离开；确认后立即锁屏。"
  case .awayWeak,.awayMissing: return "已判定离开，锁屏请求结果见下方事件记录。"
  case .stale: return "目标信号过期，等待新信号或失联判定。"
  case .pendingReturn: return "信号恢复，正在确认返回工位。"
  case .uncalibrated: return "等待有效校准。"
  }
 }
 private var targetCard: some View {
  card {
   HStack(alignment:.top) {
    Image(systemName:"applewatch").font(.system(size:30)).foregroundStyle(accent).frame(width:42)
    VStack(alignment:.leading,spacing:6) {
     Text(model.selectedID == nil ? "尚未选择目标手表" : model.selectedName).font(.headline)
     if let id=model.selectedID {
      Text(id.uuidString).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
      Text("身份：用户已确认 · 只跟踪这个设备").font(.caption).foregroundStyle(.secondary)
     } else { Text("在左侧选中设备，再点击确认。").font(.callout).foregroundStyle(.secondary) }
    }
    Spacer()
    Text(stateLabel).font(.callout.weight(.medium)).foregroundStyle(stateColor).multilineTextAlignment(.trailing)
   }
  }
 }
 private var signalCard: some View {
  card {
   VStack(alignment:.leading,spacing:16) {
    HStack {
     Text("信号趋势").font(.headline)
     Spacer()
     Text("最近 120 秒").font(.caption).foregroundStyle(.secondary)
    }
    HStack(spacing:34) {
     metric("最新 RSSI",value:model.chartSamples.last.map { "\($0.sample.rssi)" } ?? "—",unit:"dBm")
     metric("平滑信号",value:model.snapshot.ema.map { String(format:"%.1f",$0) } ?? "—",unit:"dBm")
     metric("信号年龄",value:model.snapshot.lastSample.map { "\(age($0))" } ?? "—",unit:"秒")
    }
    if model.chartSamples.isEmpty {
     VStack(spacing:8) {
      Image(systemName:"waveform.path").font(.system(size:28)).foregroundStyle(accent.opacity(0.65))
      Text(model.selectedID == nil ? "选择手表后显示信号曲线" : "等待选定设备的新信号").font(.callout)
      Text("熄屏后的采样频率需要实机验证").font(.caption).foregroundStyle(.secondary)
     }.frame(maxWidth:.infinity).frame(height:155).background(accent.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
    } else {
     Chart {
      ForEach(model.chartSamples) { point in
       LineMark(x:.value("时间",point.sample.timestamp),y:.value("dBm",Double(point.sample.rssi)))
        .foregroundStyle(by:.value("信号","原始 RSSI"))
       if let ema=point.ema {
        LineMark(x:.value("时间",point.sample.timestamp),y:.value("dBm",ema))
         .foregroundStyle(by:.value("信号","平滑信号"))
       }
      }
      if let c=model.calibration {
       RuleMark(y:.value("离开阈值",c.awayThreshold)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth:1,dash:[5,4]))
       RuleMark(y:.value("返回阈值",c.returnThreshold)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth:1,dash:[5,4]))
      }
     }.chartForegroundStyleScale(["原始 RSSI":Color.gray.opacity(0.55),"平滑信号":accent])
      .chartYScale(domain:-110 ... -20)
      .chartXScale(domain:model.currentTime.addingTimeInterval(-120)...model.currentTime)
      .frame(height:180)
    }
   }
  }
 }
 private var calibrationCard: some View {
  card {
   VStack(alignment:.leading,spacing:12) {
    HStack { Text("两步校准").font(.headline);Spacer();Text(model.calibration == nil ? "尚未完成" : "已保存").font(.caption).foregroundStyle(.secondary) }
    Text("先坐在工位采集 20 秒，再在希望锁屏的位置采集 20 秒；每组至少需要 10 个有效样本。")
     .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    HStack(spacing:12) {
     Button("1  采集工位信号") { model.beginCalibration(.near) }.disabled(!model.isRunning || model.selectedID == nil || model.calibrationPhase != nil)
     Button("2  采集离开信号") { model.beginCalibration(.far) }.disabled(!model.isRunning || !model.nearReady || model.calibrationPhase != nil)
    }.buttonStyle(.bordered)
    if let phase=model.calibrationPhase {
     ProgressView(value:model.calibrationProgress)
     Text("正在采集\(phase == .near ? "工位" : "离开")信号 · \(model.calibrationSampleCount) 个样本 · \(max(0,20-Int(model.calibrationProgress*20))) 秒剩余")
      .font(.caption).foregroundStyle(.secondary)
    } else if model.nearReady { Text("工位采样完成。点击第 2 步后带着手表走开，保持在目标位置直到 20 秒结束。") .font(.caption).foregroundStyle(accent) }
    if let c=model.calibration {
     Text(String(format:"离开阈值 %.1f dBm，持续 8 秒 · 返回阈值 %.1f dBm，持续 3 秒",c.awayThreshold,c.returnThreshold)).font(.caption).foregroundStyle(.secondary)
    }
   }
  }
 }
 private var eventCard: some View {
  card {
   VStack(alignment:.leading,spacing:12) {
    HStack {
     Text("锁屏记录").font(.headline);Spacer()
     Button("导出采集 CSV",systemImage:"square.and.arrow.up") { export() }.disabled(model.selectedID == nil)
    }
    if model.lockAttempts.isEmpty { Text("尚无锁屏请求。完成校准、开启自动锁屏并建立在场状态后，再测试离开。").font(.callout).foregroundStyle(.secondary) }
    ForEach(model.lockAttempts.suffix(8).reversed()) { attempt in
     HStack {
      Image(systemName:attempt.result == .requested ? "lock.fill" : "exclamationmark.triangle.fill").foregroundStyle(.orange)
      Text(attempt.result == .requested ? "已发送锁屏请求：\(triggerLabel(attempt.trigger))" : "锁屏失败：\(attempt.detail)")
      Spacer();Text(attempt.timestamp,style:.time).monospacedDigit().foregroundStyle(.secondary)
     }.font(.caption)
    }
    if !model.automaticLockEnabled && !model.events.isEmpty {
     Text("累计离开判定 \(model.events.count) 次；自动锁屏关闭期间的判定不会补执行。")
      .font(.caption).foregroundStyle(.secondary)
    }
    if model.droppedLogCount > 0 { Text("日志容量已满，较早的 \(model.droppedLogCount) 条记录已截断。").font(.caption).foregroundStyle(.orange) }
   }
  }
 }
 private func triggerLabel(_ trigger: LockTrigger) -> String {
  switch trigger { case .manual: "手动测试";case .weakSignal: "信号持续弱";case .missingSignal: "信号丢失" }
 }
 private func card<Content:View>(@ViewBuilder _ content: () -> Content) -> some View {
  content().frame(maxWidth:.infinity,alignment:.leading).padding(18)
   .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.06)))
 }
 private func metric(_ label:String,value:String,unit:String) -> some View {
  VStack(alignment:.leading,spacing:5) {
   Text(label).font(.caption).foregroundStyle(.secondary)
   HStack(alignment:.firstTextBaseline,spacing:4) { Text(value).font(.system(size:26,weight:.medium,design:.rounded)).monospacedDigit();Text(unit).font(.caption).foregroundStyle(.secondary) }
  }
 }
 private func age(_ date:Date) -> Int { max(0,Int(model.currentTime.timeIntervalSince(date))) }
 private var scannerLabel: String {
  if !model.requestedScanning { return "已暂停" }
  switch model.availability {
  case .ready: return model.isRunning ? "扫描中" : "等待恢复"
  case .unauthorized: return "需要蓝牙权限：系统设置 → 隐私与安全性 → 蓝牙"
  case .poweredOff: return "请打开 Mac 蓝牙"
  case .unsupported: return "设备不支持蓝牙扫描"
  case .unavailable: return "等待蓝牙就绪"
  }
 }
 private var stateLabel: String {
  if !model.requestedScanning { return "已暂停" }
  if !model.isRunning { return "蓝牙不可用" }
  if model.selectedID == nil { return "等待选择" }
  switch model.snapshot.state {
  case .uncalibrated: return "等待校准"
  case .warmingUp: return "请回到工位 · 尚未生效"
  case .present: return "在工位附近"
  case .pendingAway: return "信号变弱 · 正在确认"
  case .awayWeak: return "已判定离开"
  case .stale: return "目标信号过期"
  case .awayMissing: return "目标信号丢失 · 可能需重新选择"
  case .pendingReturn: return "信号恢复 · 正在确认"
  case .returned: return "已返回"
  }
 }
 private var stateColor: Color {
  switch model.snapshot.state { case .awayWeak,.awayMissing,.stale: .orange; case .present,.returned: .green; default: .secondary }
 }
 private func export() {
  let panel=NSSavePanel();panel.allowedContentTypes=[.commaSeparatedText];panel.nameFieldStringValue="WatchSignal-\(Date().formatted(.iso8601).replacingOccurrences(of:":",with:"-")) .csv".replacingOccurrences(of:" .csv",with:".csv")
  guard panel.runModal() == .OK,let url=panel.url else { return }
  do { try model.exportCSV().write(to:url,atomically:true,encoding:.utf8) }
  catch { model.errorMessage="导出失败：\(error.localizedDescription)" }
 }
}
