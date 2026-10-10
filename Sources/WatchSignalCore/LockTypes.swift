import Foundation

public enum LockTrigger: String, Sendable { case weakSignal, missingSignal, manual }
public enum LockResult: String, Sendable { case requested, failed }
public struct LockAttempt: Identifiable, Sendable {
 public let id = UUID()
 public let timestamp: Date
 public let trigger: LockTrigger
 public let result: LockResult
 public let detail: String
 public init(timestamp: Date, trigger: LockTrigger, result: LockResult, detail: String = "") {
  self.timestamp=timestamp;self.trigger=trigger;self.result=result;self.detail=detail
 }
}
