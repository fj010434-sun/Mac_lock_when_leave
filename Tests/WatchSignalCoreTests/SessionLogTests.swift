import Foundation
import WatchSignalCore
@MainActor func registerLogTests(_ suite: TestSuite) {
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
