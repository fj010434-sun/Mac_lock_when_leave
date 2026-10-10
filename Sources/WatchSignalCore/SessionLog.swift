import Foundation
public final class SessionLog {
 private struct Row {
  let sample: SignalSample?; let snapshot: PresenceSnapshot?; let event: SimulationEvent?
  let configurationTime: Date?; let calibration: Calibration?; let version: Int
 }
 private var rows: [Row] = []
 private let capacity: Int
 private var currentCalibration: Calibration?, version=0
 public private(set) var droppedCount=0
 public init(capacity: Int = 50_000) { self.capacity=max(1,capacity) }
 private func append(_ row: Row) {
  if rows.count >= capacity { rows.removeFirst(); droppedCount += 1 }
  rows.append(row)
 }
 public func setCalibration(_ calibration: Calibration?, at: Date) {
  currentCalibration=calibration;version += 1
  append(Row(sample:nil,snapshot:nil,event:nil,configurationTime:at,calibration:calibration,version:version))
 }
 public func append(sample: SignalSample, snapshot: PresenceSnapshot) {
  append(Row(sample:sample,snapshot:snapshot,event:nil,configurationTime:nil,calibration:currentCalibration,version:version))
 }
 public func append(event: SimulationEvent) {
  append(Row(sample:nil,snapshot:nil,event:event,configurationTime:nil,calibration:currentCalibration,version:version))
 }
 public func csv(deviceID: UUID, name: String, calibration: Calibration?) -> String {
  func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
  let format=ISO8601DateFormatter();format.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
  var lines=["device_uuid,"+quote(deviceID.uuidString),"device_name,"+quote(name),"truncated,\(droppedCount)"]
  if let c=calibration { lines += ["near_median,\(c.nearMedian)","far_median,\(c.farMedian)","near_count,\(c.nearCount)","far_count,\(c.farCount)","calibrated_at,\(format.string(from:c.createdAt))","away_threshold,\(c.awayThreshold)","return_threshold,\(c.returnThreshold)"] }
  lines.append("timestamp,device_uuid,rssi,ema,state,event_reason,calibration_version,near_median,far_median,away_threshold,return_threshold,near_count,far_count,calibrated_at")
  for row in rows {
   var columns: [String]
   if let s=row.sample, s.deviceID == deviceID {
    columns=[format.string(from:s.timestamp),deviceID.uuidString,String(s.rssi),row.snapshot?.ema.map(String.init(describing:)) ?? "",row.snapshot?.state.rawValue ?? "",""]
   } else if let e=row.event {
    columns=[format.string(from:e.timestamp),deviceID.uuidString,"","","simulation",e.reason.rawValue]
   } else if let date=row.configurationTime {
    columns=[format.string(from:date),deviceID.uuidString,"","","configuration","calibrationChanged"]
   } else { continue }
   columns.append(String(row.version))
   if let c=row.calibration {
    columns += [String(c.nearMedian),String(c.farMedian),String(c.awayThreshold),String(c.returnThreshold),String(c.nearCount),String(c.farCount),format.string(from:c.createdAt)]
   } else { columns += Array(repeating:"",count:7) }
   lines.append(columns.joined(separator:","))
  }
  return lines.joined(separator:"\n")+"\n"
 }
}
