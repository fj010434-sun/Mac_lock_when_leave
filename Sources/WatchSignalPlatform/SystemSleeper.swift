import Foundation

// Retain the existing action interface so calibration and departure handling stay unchanged.
@MainActor public final class SystemSleeper: ScreenLocking {
 public typealias Completion = @MainActor @Sendable (Result<Void, Error>) -> Void
 public typealias Runner = @MainActor (URL, [String], @escaping Completion) throws -> Void
 private let run: Runner
 public var onSleepResult: Completion?
 public init(run: @escaping Runner = SystemSleeper.runCommand) { self.run=run }
 // pmset sleepnow does not post keyboard events or require Accessibility access.
 public var isAuthorized: Bool { true }
 public func requestAuthorization() {}
 public func lock() throws {
  try run(URL(fileURLWithPath:"/usr/bin/pmset"),["sleepnow"]) { [weak self] result in
   self?.onSleepResult?(result)
  }
 }
 public static func runCommand(_ url: URL, _ args: [String], completion: @escaping Completion) throws {
  let process=Process()
  process.executableURL=url;process.arguments=args
  process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
  process.terminationHandler={ finished in
   let status=finished.terminationStatus
   Task { @MainActor in
    completion(status == 0 ? .success(()) : .failure(SystemSleepError.commandFailed(status)))
   }
  }
  // Do not block the main actor while the machine enters sleep or wakes.
  try process.run()
 }
}

public enum SystemSleepError: LocalizedError, Sendable {
 case commandFailed(Int32)
 public var errorDescription: String? {
  switch self { case .commandFailed(let status): "系统休眠命令失败（退出码 \(status)）。" }
 }
}
