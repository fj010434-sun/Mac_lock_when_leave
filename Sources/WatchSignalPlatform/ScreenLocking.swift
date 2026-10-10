import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox

@MainActor public protocol ScreenLocking: AnyObject {
 var isAuthorized: Bool { get }
 func requestAuthorization()
 func lock() throws
}

public enum ScreenLockError: LocalizedError, Sendable {
 case permissionDenied, eventCreationFailed, unavailable, displaySleepFailed(Int32)
 public var errorDescription: String? {
  switch self {
  case .permissionDenied: "请在系统设置 → 隐私与安全性 → 辅助功能中允许手表离开锁屏，再重新启用自动锁屏。"
  case .eventCreationFailed: "无法创建系统锁屏快捷键事件。"
  case .unavailable: "锁屏执行器不可用。"
  case .displaySleepFailed(let code): "关闭显示器命令失败（退出码 \(code)）。"
  }
 }
}

@MainActor public final class SystemScreenLocker: ScreenLocking {
 private let authorized: @MainActor () -> Bool
 private let postShortcut: @MainActor () throws -> Void
 private let sleepDisplay: @MainActor () async throws -> Void
 public var onDisplaySleepResult: (@MainActor (Result<Void, Error>) -> Void)?
 public init(authorized: @escaping @MainActor () -> Bool = { CGPreflightPostEventAccess() },
             postShortcut: @escaping @MainActor () throws -> Void = SystemScreenLocker.postSystemShortcut,
             sleepDisplay: @escaping @MainActor () async throws -> Void = SystemScreenLocker.sleepSystemDisplay) {
  self.authorized=authorized;self.postShortcut=postShortcut;self.sleepDisplay=sleepDisplay
 }
 public var isAuthorized: Bool { authorized() }
 public func requestAuthorization() {
  _ = CGRequestPostEventAccess()
  if !isAuthorized, let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
   NSWorkspace.shared.open(url)
  }
 }
 // Create both events before posting anything, so failure cannot leave a key down.
 public static func makeShortcutEvents() throws -> [CGEvent] {
  guard let source=CGEventSource(stateID:.privateState),
        let down=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_ANSI_Q),keyDown:true),
        let up=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_ANSI_Q),keyDown:false) else {
   throw ScreenLockError.eventCreationFailed
  }
  down.flags=[.maskControl,.maskCommand];up.flags=[.maskControl,.maskCommand]
  return [down,up]
 }
 public func lock() throws {
  guard isAuthorized else { throw ScreenLockError.permissionDenied }
  try postShortcut()
  // CGEvent.post has no acknowledgement: success means requested, not confirmed locked.
  Task { [weak self] in
   // Allow the posted lock events to enter the system queue before sleeping the display.
   // This is an ordering delay, not a confirmation that the system has locked.
   do { try await Task.sleep(for:.milliseconds(750)) } catch { return }
   guard let self else { return }
   do {
    try await self.sleepDisplay()
    self.onDisplaySleepResult?(.success(()))
   } catch { self.onDisplaySleepResult?(.failure(error)) }
  }
 }
 @usableFromInline static func postSystemShortcut() throws {
  for event in try makeShortcutEvents() { event.post(tap:.cgSessionEventTap) }
 }
 @usableFromInline static func sleepSystemDisplay() async throws {
  try await Task.detached(priority:.userInitiated) {
   let process=Process()
   process.executableURL=URL(fileURLWithPath:"/usr/bin/pmset")
   process.arguments=["displaysleepnow"]
   process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
   try process.run();process.waitUntilExit()
   guard process.terminationStatus == 0 else { throw ScreenLockError.displaySleepFailed(process.terminationStatus) }
  }.value
 }
}
