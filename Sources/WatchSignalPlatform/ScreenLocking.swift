import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox

@MainActor public protocol ScreenLocking: AnyObject {
 var isAuthorized: Bool { get }
 func requestAuthorization()
 func lock() throws
}

public enum ScreenLockError: LocalizedError {
 case permissionDenied, eventCreationFailed, unavailable
 public var errorDescription: String? {
  switch self {
  case .permissionDenied: "请在系统设置 → 隐私与安全性 → 辅助功能中允许手表离开锁屏，再重新启用自动锁屏。"
  case .eventCreationFailed: "无法创建系统锁屏快捷键事件。"
  case .unavailable: "锁屏执行器不可用。"
  }
 }
}

@MainActor public final class SystemScreenLocker: ScreenLocking {
 public init() {}
 public var isAuthorized: Bool { CGPreflightPostEventAccess() }
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
  for event in try Self.makeShortcutEvents() { event.post(tap:.cgSessionEventTap) }
  // CGEvent.post has no acknowledgement: success means requested, not confirmed locked.
 }
}
