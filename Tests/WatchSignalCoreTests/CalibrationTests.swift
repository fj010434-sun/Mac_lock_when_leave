import Foundation
import WatchSignalCore
let targetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let otherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
func time(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
func sample(_ seconds: Double, _ rssi: Int, _ id: UUID = targetID) -> SignalSample { SignalSample(deviceID: id, timestamp: time(seconds), rssi: rssi) }
func calibration() -> Calibration { Calibration(nearMedian: -45, farMedian: -65, nearCount: 10, farCount: 10, createdAt: time(40)) }
@MainActor func registerCalibrationTests(_ suite: TestSuite) {
 suite.test("Core.testCalibrationRequiresTwentySecondsAndTenSamples") {
  let c = CalibrationCollector(deviceID: targetID)
  c.start(phase: .near, at: time(0))
  for i in 0..<10 { c.ingest(sample(Double(i), -45)) }
  try expectThrow { _ = try c.finish(at: time(19)) }
  try check(try c.finish(at: time(20)) == nil)
  c.start(phase: .far, at: time(21))
  for i in 0..<9 { c.ingest(sample(Double(i + 21), -65)) }
  try expectThrow { _ = try c.finish(at: time(41)) }
 }
 suite.test("Core.testCalibrationThresholdAndSeparation") {
  for (far, allowed) in [(-65, true), (-55, true), (-54, false)] {
   let c = CalibrationCollector(deviceID: targetID)
   c.start(phase: .near, at: time(0)); for i in 0..<10 { c.ingest(sample(Double(i), -45)) }; _ = try c.finish(at: time(20))
   c.start(phase: .far, at: time(21)); for i in 0..<10 { c.ingest(sample(Double(i + 21), far)) }
   if allowed {
    let optional = try c.finish(at: time(41))
    try check(optional != nil, "expected calibration")
    guard let result = optional else { return }
    if far == -65 { try check(result.awayThreshold == -55 && result.returnThreshold == -49) }
   } else { try expectThrow { _ = try c.finish(at: time(41)) } }
  }
 }
 suite.test("Core.testCalibrationFiltersTargetAndWindow") {
  let c = CalibrationCollector(deviceID: targetID); c.start(phase: .near, at: time(0))
  for i in 0..<9 { c.ingest(sample(Double(i), -45)) }
  c.ingest(sample(9, -45, otherID)); c.ingest(sample(21, -45)); c.ingest(sample(10, 127))
  try expectThrow { _ = try c.finish(at: time(22)) }
 }
}
