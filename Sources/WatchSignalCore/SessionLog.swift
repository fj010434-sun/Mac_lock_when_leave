import Foundation
public final class SessionLog {
 private struct Row { let sample: SignalSample?; let snapshot: PresenceSnapshot?; let event: SimulationEvent? }
 private var rows: [Row] = []
 private let capacity: Int
 public private(set) var droppedCount=0
 public init(capacity: Int = 50_000) { self.capacity=max(1,capacity) }
 private func append(_ row: Row) {
  if rows.count >= capacity { rows.removeFirst(); droppedCount += 1 }
  rows.append(row)
 }
 public func append(sample: SignalSample, snapshot: PresenceSnapshot) { append(Row(sample: sample, snapshot: snapshot, event: nil)) }
 public func append(event: SimulationEvent) { append(Row(sample: nil, snapshot: nil, event: event)) }
 public func csv(deviceID: UUID, name: String, calibration: Calibration?) -> String {
  func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
  let format=ISO8601DateFormatter(); format.formatOptions=[.withInternetDateTime, .withFractionalSeconds]
  var lines=["device_uuid,"+quote(deviceID.uuidString), "device_name,"+quote(name), "truncated,\(droppedCount)"]
  if let c=calibration { lines += ["near_median,\(c.nearMedian)", "far_median,\(c.farMedian)", "near_count,\(c.nearCount)", "far_count,\(c.farCount)", "calibrated_at,\(format.string(from: c.createdAt))", "away_threshold,\(c.awayThreshold)", "return_threshold,\(c.returnThreshold)"] }
  lines.append("timestamp,device_uuid,rssi,ema,state,event_reason")
  for row in rows {
   if let s=row.sample, s.deviceID == deviceID {
    lines.append([format.string(from:s.timestamp),deviceID.uuidString,String(s.rssi),row.snapshot?.ema.map(String.init(describing:)) ?? "",row.snapshot?.state.rawValue ?? "", ""].joined(separator:","))
   } else if let e=row.event {
    lines.append([format.string(from:e.timestamp),deviceID.uuidString,"","","simulation",e.reason.rawValue].joined(separator:","))
   }
  }
  return lines.joined(separator:"\n")+"\n"
 }
}
