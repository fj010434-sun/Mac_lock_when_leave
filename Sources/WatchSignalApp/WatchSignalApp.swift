import AppKit
import SwiftUI
import WatchSignalPlatform
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 private let locker=SystemSleeper()
 lazy var model: DiagnosticModel = {
  let model=DiagnosticModel(scanner:BluetoothScanner(),store:SelectionStore(),locker:locker)
  locker.onSleepResult={ [weak model] result in model?.recordSystemSleep(result) }
  return model
 }()
 private var timer: Timer?
 private var observers: [NSObjectProtocol]=[]
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular)
  timer=Timer(timeInterval:1,repeats:true) { [weak self] _ in
   MainActor.assumeIsolated { self?.model.advance(at:Date()) }
  }
  if let timer { RunLoop.main.add(timer,forMode:.common) }
  let center=NSWorkspace.shared.notificationCenter
  observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.model.handleSleep() } })
  observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.model.handleWake() } })
  NSApp.activate(ignoringOtherApps:true)
 }
 func applicationWillTerminate(_ notification: Notification) {
  model.pause();timer?.invalidate()
  for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
 }
}
@main struct WatchSignalApp: App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
 @Environment(\.openWindow) private var openWindow
 var body: some Scene {
  Window("手表离开锁屏", id:"diagnostic") {
   DiagnosticView(model:delegate.model)
  }.defaultSize(width:1080,height:760)
  MenuBarExtra("手表离开锁屏",systemImage:"applewatch") {
   Button("打开主窗口") { openWindow(id:"diagnostic");NSApp.activate(ignoringOtherApps:true) }
   Button(delegate.model.requestedScanning ? "暂停扫描" : "开始扫描") {
    if delegate.model.requestedScanning { delegate.model.pause() } else { delegate.model.start() }
   }
   Divider()
   Text(delegate.model.automaticLockEnabled ? "自动休眠已开启" : "自动休眠已关闭")
   if delegate.model.automaticLockEnabled { Button("关闭自动休眠") { delegate.model.setAutomaticLock(false) } }
   Button("立即休眠") { delegate.model.lockNow() }
   Button("退出") { NSApp.terminate(nil) }
  }
 }
}
