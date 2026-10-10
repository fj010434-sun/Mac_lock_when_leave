import Foundation
import WatchSignalCore
func established() -> PresenceDetector {
 let d = PresenceDetector(deviceID: targetID, calibration: calibration())
 for i in 0..<5 { d.ingest(sample(Double(i), -45)) }
 return d
}
@MainActor func registerPresenceTests(_ suite: TestSuite) {
 suite.test("Core.testOtherTargetAndInvalidRSSIAreIgnored") {
  let d = established(); let before = d.snapshot
  for value in [-100, -45] { d.ingest(sample(10, value, otherID)) }
  for value in [127, 0, -128] { d.ingest(sample(10, value)) }
  try check(d.snapshot == before)
  let valid = PresenceDetector(deviceID: targetID, calibration: nil)
  valid.ingest(sample(0, -127)); try check(valid.snapshot.ema == -127)
  valid.ingest(sample(1, -1)); try check(valid.snapshot.ema == -95.5)
 }
 suite.test("Core.testEMAAndWarmup") {
  let d = PresenceDetector(deviceID: targetID, calibration: calibration())
  d.ingest(sample(0, -45)); d.ingest(sample(1, -65)); try check(d.snapshot.ema == -50)
  try check(d.snapshot.state == .warmingUp)
 }
 suite.test("Core.testContinuousWeakSignalEightSecondsOnlyOnce") {
  let d = established()
  // -45 -> -50 -> -53.75 -> -56.5625: pending starts at t=7.
  for i in 5...14 { d.ingest(sample(Double(i), -65)) }
  d.tick(at: time(14.99)); try check(d.events.isEmpty)
  d.ingest(sample(15, -65)); try check(d.snapshot.state == .awayWeak && d.events.count == 1)
  d.tick(at: time(16)); try check(d.events.count == 1)
 }
 suite.test("Core.testShortDipCancelsAwayTimer") {
  let d = established()
  for i in 5...9 { d.ingest(sample(Double(i), -65)) }
  for i in 10...12 { d.ingest(sample(Double(i), -20)) }
  try check(d.snapshot.state == .present)
  d.tick(at: time(13)); try check(d.events.isEmpty)
 }
 suite.test("Core.testHysteresisAndThreeSecondReturn") {
  let d = established(); for i in 5...15 { d.ingest(sample(Double(i), -65)) }
  for i in 16...30 { d.ingest(sample(Double(i), -52)) }
  try check(d.snapshot.state == .awayWeak)
  d.ingest(sample(31, -20)); try check(d.snapshot.state == .pendingReturn)
  d.tick(at: time(33.99)); try check(d.snapshot.state == .pendingReturn)
  d.tick(at: time(34)); try check(d.snapshot.state == .returned)
 }
 suite.test("Core.testFreshnessBoundaryAndMissingSignal") {
  let d = established(); d.tick(at: time(9)); try check(d.snapshot.state == .present)
  d.tick(at: time(9.01)); try check(d.snapshot.state == .stale)
  d.ingest(sample(23, -45, otherID)); d.tick(at: time(23.99)); try check(d.events.isEmpty)
  d.tick(at: time(24)); try check(d.snapshot.state == .awayMissing && d.events.count == 1)
  d.tick(at: time(60)); try check(d.events.count == 1)
  d.ingest(sample(61, -80)); try check(d.snapshot.ema == -80 && d.snapshot.state == .warmingUp)
  d.tick(at: time(90)); try check(d.events.count == 1)
 }
 suite.test("Core.testStaleCancelsContinuousWeakTimer") {
  let d = established(); for i in 5...9 { d.ingest(sample(Double(i), -65)) }
  d.tick(at: time(14.1)); try check(d.snapshot.state == .stale)
  d.ingest(sample(16, -65)); d.tick(at: time(17)); try check(d.events.isEmpty)
 }
 suite.test("Core.testResetAndRecalibrationNeedBaseline") {
  let d = established(); d.reset(); try check(d.snapshot.ema == nil)
  d.tick(at: time(100)); try check(d.events.isEmpty)
  for i in 100...110 { d.ingest(sample(Double(i), -80)) }
  try check(d.events.isEmpty)
  d.setCalibration(nil); try check(d.snapshot.state == .uncalibrated)
  d.tick(at: time(200)); try check(d.events.isEmpty)
 }
 suite.test("Core.testNoBaselineMeansNoMissingEvent") {
  let d = PresenceDetector(deviceID: targetID, calibration: calibration())
  for i in 0..<4 { d.ingest(sample(Double(i), -45)) }
  d.tick(at: time(100)); try check(d.events.isEmpty)
  let u = PresenceDetector(deviceID: targetID, calibration: nil)
  for i in 0..<10 { u.ingest(sample(Double(i), -45)) }; u.tick(at: time(100)); try check(u.events.isEmpty)
 }
}
