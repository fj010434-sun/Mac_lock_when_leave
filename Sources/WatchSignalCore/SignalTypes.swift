import Foundation
public struct SignalSample: Equatable, Sendable {
 public let deviceID: UUID; public let timestamp: Date; public let rssi: Int
 public init(deviceID: UUID, timestamp: Date, rssi: Int) { self.deviceID=deviceID; self.timestamp=timestamp; self.rssi=rssi }
 public var isValid: Bool { (-127 ... -1).contains(rssi) }
}
public struct Calibration: Codable, Equatable, Sendable {
 public let nearMedian: Double; public let farMedian: Double; public let nearCount: Int; public let farCount: Int; public let createdAt: Date
 public init(nearMedian: Double, farMedian: Double, nearCount: Int, farCount: Int, createdAt: Date) { self.nearMedian=nearMedian; self.farMedian=farMedian; self.nearCount=nearCount; self.farCount=farCount; self.createdAt=createdAt }
 public var awayThreshold: Double { (nearMedian + farMedian) / 2 }
 public var returnThreshold: Double { awayThreshold + 6 }
 public var isValid: Bool { nearMedian.isFinite && farMedian.isFinite && (-127 ... -1).contains(nearMedian) && (-127 ... -1).contains(farMedian) && nearMedian-farMedian >= 10 && nearCount >= 10 && farCount >= 10 }
}
public enum CalibrationPhase: String, Sendable { case near, far }
public enum PresenceState: String, Sendable { case uncalibrated, warmingUp, present, pendingAway, awayWeak, stale, awayMissing, pendingReturn, returned }
public struct PresenceSnapshot: Equatable, Sendable {
 public var state: PresenceState; public var ema: Double?; public var lastSample: Date?
 public init(state: PresenceState, ema: Double? = nil, lastSample: Date? = nil) { self.state=state; self.ema=ema; self.lastSample=lastSample }
}
public enum SimulationReason: String, Sendable { case weakSignal, missingSignal }
public struct SimulationEvent: Equatable, Identifiable, Sendable {
 public let id = UUID(); public let timestamp: Date; public let reason: SimulationReason
 public init(timestamp: Date, reason: SimulationReason) { self.timestamp=timestamp; self.reason=reason }
}
