import Foundation
public enum CalibrationError: LocalizedError {
 case timeInsufficient, samplesInsufficient, separationInsufficient, nearRequired
 public var errorDescription: String? {
  switch self {
  case .timeInsufficient: "请采集满 20 秒。"
  case .samplesInsufficient: "有效样本不足 10 个，请重新采集；可能是手表广播不够持续。"
  case .separationInsufficient: "信号区分不足 10 dB，请重新校准。"
  case .nearRequired: "请先完成工位采样。"
  }
 }
}
public final class CalibrationCollector {
 private let deviceID: UUID
 private var phase: CalibrationPhase?; private var startTime: Date?
 private var values: [Double] = []; private var near: (Double, Int)?
 public private(set) var sampleCount = 0
 public init(deviceID: UUID) { self.deviceID=deviceID }
 public func start(phase: CalibrationPhase, at: Date) {
  self.phase=phase; startTime=at; values=[]; sampleCount=0
  if phase == .near { near=nil }
 }
 public func ingest(_ sample: SignalSample) {
  guard sample.deviceID == deviceID, sample.isValid, let startTime else { return }
  let elapsed=sample.timestamp.timeIntervalSince(startTime)
  guard elapsed >= 0 && elapsed < 20 else { return }
  values.append(Double(sample.rssi)); sampleCount=values.count
 }
 public func finish(at: Date) throws -> Calibration? {
  guard let startTime, let phase, at.timeIntervalSince(startTime) >= 20 else { throw CalibrationError.timeInsufficient }
  guard values.count >= 10 else { throw CalibrationError.samplesInsufficient }
  let sorted=values.sorted(), n=sorted.count
  let median = n % 2 == 0 ? (sorted[n/2-1]+sorted[n/2])/2 : sorted[n/2]
  if phase == .near { near=(median,n); self.phase=nil; return nil }
  guard let near else { throw CalibrationError.nearRequired }
  guard near.0-median >= 10 else { throw CalibrationError.separationInsufficient }
  self.phase=nil
  return Calibration(nearMedian: near.0, farMedian: median, nearCount: near.1, farCount: n, createdAt: at)
 }
}
