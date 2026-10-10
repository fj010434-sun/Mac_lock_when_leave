import AppKit
import SwiftUI
import WatchSignalPlatform
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 let model=DiagnosticModel(scanner:BluetoothScanner(),store:SelectionStore())
 private var timer: Timer?
 private var observers: [NSObjectProtocol]=[]
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular)
  timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
   MainActor.assumeIsolated { self?.model.advance(at:Date()) }
  }
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
  Window("手表信号诊断", id:"diagnostic") {
   DiagnosticView(model:delegate.model)
  }.defaultSize(width:1080,height:760)
  MenuBarExtra("手表信号诊断",systemImage:"applewatch") {
   Button("打开诊断窗口") { openWindow(id:"diagnostic");NSApp.activate(ignoringOtherApps:true) }
   Button(delegate.model.requestedScanning ? "暂停扫描" : "开始扫描") {
    if delegate.model.requestedScanning { delegate.model.pause() } else { delegate.model.start() }
   }
   Divider()
   Text("诊断模式 · 不会实际锁屏")
   Button("退出") { NSApp.terminate(nil) }
  }
 }
}
