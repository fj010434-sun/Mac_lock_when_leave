import Foundation
import WatchSignalCore
@MainActor func registerLogTests(_ suite: TestSuite) {
 suite.test("Core.testMultipleCalibrationsKeepPerRecordThresholds") {
  let log=SessionLog();let d=established()
  log.setCalibration(calibration(), at:time(0));log.append(sample:sample(1,-45),snapshot:d.snapshot)
  let next=Calibration(nearMedian:-35,farMedian:-55,nearCount:10,farCount:10,createdAt:time(40))
  log.setCalibration(next, at:time(40));log.append(sample:sample(41,-35),snapshot:d.snapshot)
  let csv=log.csv(deviceID:targetID,name:"A",calibration:next)
  let rows=csv.split(separator:"\n").map(String.init)
  let header=rows.first { $0.hasPrefix("timestamp,") }!.split(separator:",").map(String.init)
  guard let index=header.firstIndex(of:"away_threshold"),let version=header.firstIndex(of:"calibration_version") else { throw TestFailure(message:"missing per-row calibration columns") }
  let data=rows.filter { $0.contains(",present,") }.map { $0.split(separator:",",omittingEmptySubsequences:false).map(String.init) }
  try check(data.count == 2 && data[0][index] == "-55.0" && data[1][index] == "-45.0")
  try check(data[0][version] == "1" && data[1][version] == "2")
 }

 suite.test("Core.testCSVFiltersDeviceAndEscapesName") {
  let log = SessionLog(); let d = established()
  log.append(sample: sample(0, -45), snapshot: d.snapshot)
  log.append(sample: sample(1, -100, otherID), snapshot: d.snapshot)
  log.append(event: SimulationEvent(timestamp: time(20), reason: .weakSignal))
  let csv = log.csv(deviceID: targetID, name: "我的,\"手表\"\nA", calibration: calibration())
  try check(csv.contains("\"我的,\"\"手表\"\"\nA\""))
  try check(!csv.contains(otherID.uuidString) && csv.contains("-55") && csv.contains("weakSignal"))
 }
 suite.test("Core.testLogTruncationIsReported") {
  let log = SessionLog(capacity: 2); let d = established()
  for i in 0..<3 { log.append(sample: sample(Double(i), -45), snapshot: d.snapshot) }
  try check(log.droppedCount == 1 && log.csv(deviceID: targetID, name: "A", calibration: nil).contains("truncated,1"))
 }
}
