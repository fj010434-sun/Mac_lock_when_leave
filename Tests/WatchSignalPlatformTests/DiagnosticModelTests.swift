import Foundation
import WatchSignalCore
import WatchSignalPlatform
@MainActor final class FakeScanner: SignalScanning {
 var onSample: ((SignalSample, String?) -> Void)?
 var onAvailability: ((ScannerAvailability) -> Void)?
 func start() { onAvailability?(.ready) }
 func stop() {}
 func send(_ s: SignalSample, name: String = "同名手表") { onSample?(s, name) }
}
@MainActor func fixture() -> (DiagnosticModel, FakeScanner, SelectionStore) {
 let s=FakeScanner(), store=SelectionStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("selection.json"))
 let m=DiagnosticModel(scanner:s,store:store,now:{ time(0) }); m.start(); m.select(deviceID:targetID,name:"我的表")
 return (m,s,store)
}
@MainActor func seed(_ m: DiagnosticModel, _ s: FakeScanner, _ store: SelectionStore) throws -> DiagnosticModel {
 try store.save(SavedSelection(deviceID: targetID, name: "我的表", calibration: calibration()))
 m.pause()
 let restored=DiagnosticModel(scanner:s,store:store,now:{ time(0) }); restored.start()
 for i in 0..<5 { s.send(sample(Double(i),-45)) }
 try check(restored.snapshot.state == .present && restored.isRunning, "fixture must establish real presence")
 return restored
}
@MainActor func registerPlatformTests(_ suite: TestSuite) {
 suite.test("Platform.testRecalibrationRetainsPersistenceFailure") {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let url=root.appendingPathComponent("selection.json")
  defer { try? FileManager.default.removeItem(at:root) }
  let store=SelectionStore(url:url);try store.save(SavedSelection(deviceID:targetID,name:"A",calibration:calibration()))
  let scanner=FakeScanner(), m=DiagnosticModel(scanner:scanner,store:store,now:{time(0)})
  m.start();try FileManager.default.removeItem(at:url);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
  m.beginCalibration(.near)
  try check(m.errorMessage != nil, "save failure must remain visible during recalibration")
 }
 suite.test("Platform.testRecalibrationCSVKeepsOldThresholds") {
  let (original,s,store)=fixture();let m=try seed(original,s,store)
  m.beginCalibration(.near);m.advance(at:time(20)) // fails for insufficient samples
  let csv=m.exportCSV(), lines=csv.split(separator:"\n").map(String.init)
  let header=lines.first { $0.hasPrefix("timestamp,") }!.split(separator:",").map(String.init)
  guard let version=header.firstIndex(of:"calibration_version"),let threshold=header.firstIndex(of:"away_threshold") else { throw TestFailure(message:"rows must carry calibration version and threshold") }
  let old=lines.first { $0.contains(",present,") }!.split(separator:",",omittingEmptySubsequences:false).map(String.init)
  try check(old[threshold] == "-55.0" && old[version] == "1", "old rows keep original thresholds after failed recalibration")
  let boundary=lines.last { $0.contains(",configuration,") }!.split(separator:",",omittingEmptySubsequences:false).map(String.init)
  try check(boundary[threshold].isEmpty && boundary[version] == "2", "clear calibration boundary must be logged")
 }

 suite.test("Platform.testOtherDeviceCannotReplaceSelection") {
  let (m,s,_) = fixture(); s.send(sample(0,-45)); s.send(sample(1,-90,otherID))
  try check(m.selectedID == targetID && m.chartSamples.count == 1 && m.snapshot.lastSample == time(0))
 }
 suite.test("Platform.testRestoreWaitsForFreshTarget") {
  let (_,s,store)=fixture(); try store.save(SavedSelection(deviceID:targetID,name:"我的表",calibration:calibration()))
  let m=DiagnosticModel(scanner:s,store:store,now:{ time(0) }); m.start(); m.advance(at:time(100))
  try check(m.selectedID == targetID && m.snapshot.ema == nil && m.events.isEmpty)
 }
 suite.test("Platform.testPauseAndUnavailableCancelTimers") {
  for unavailable in [ScannerAvailability.unauthorized,.poweredOff,.unsupported,.unavailable] {
   let (original,s,store)=fixture(); let m=try seed(original,s,store)
   s.onAvailability?(unavailable); m.advance(at:time(60))
   try check(m.events.isEmpty && m.snapshot.ema == nil && !m.isRunning)
  }
  let (original,s,store)=fixture(); let m=try seed(original,s,store); m.pause()
  s.onAvailability?(.ready); m.advance(at:time(60)); s.send(sample(61,-45))
  try check(m.events.isEmpty && m.snapshot.ema == nil && !m.isRunning)
 }
 suite.test("Platform.testSleepWakeNeedsNewBaseline") {
  let (original,s,store)=fixture(); let m=try seed(original,s,store)
  m.handleSleep(); m.advance(at:time(60)); m.handleWake(); m.advance(at:time(100))
  try check(m.events.isEmpty && m.snapshot.ema == nil)
  s.send(sample(101,-80)); try check(m.snapshot.state == .warmingUp)
 }
 suite.test("Platform.testDeviceChangeDropsCalibration") {
  let (original,s,store)=fixture(); let m=try seed(original,s,store)
  m.select(deviceID:otherID,name:"另一个设备")
  try check(m.calibration == nil && m.chartSamples.isEmpty && m.events.isEmpty)
  try check(store.load()?.deviceID == otherID && store.load()?.calibration == nil)
 }
 suite.test("Platform.testExpiredSamplesArePruned") {
  let (m,s,_)=fixture(); s.send(sample(0,-45)); try check(m.chartSamples.count == 1); m.advance(at:time(121))
  try check(m.chartSamples.isEmpty)
 }
 suite.test("Platform.testCalibrationFailureAndStoreFailureAreVisible") {
  let (original,s,store)=fixture(); let m=try seed(original,s,store)
  m.beginCalibration(.near); try check(m.calibration == nil && m.snapshot.state == .uncalibrated)
  m.advance(at:time(20)); try check(m.errorMessage != nil && store.load()?.calibration == nil)
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:directory) }
  let broken=DiagnosticModel(scanner:FakeScanner(),store:SelectionStore(url:directory),now:{time(0)})
  try check(broken.errorMessage != nil)
  broken.select(deviceID:targetID,name:"A"); try check(broken.errorMessage != nil)
 }
 suite.test("Platform.testOnlyTargetSamplesCalibrateAndExport") {
  let (m,s,_) = fixture(); m.beginCalibration(.near)
  for i in 0..<10 { s.send(sample(Double(i),-45)); s.send(sample(Double(i),-100,otherID)) }
  m.advance(at:time(20)); try check(m.nearReady && m.calibrationSampleCount == 10)
  // Fake clock remains 0 for far; sample times intentionally fill its window.
  m.beginCalibration(.far); for i in 0..<10 { s.send(sample(Double(i),-65)) }; m.advance(at:time(20))
  try check(m.calibration?.awayThreshold == -55 && !m.exportCSV().contains(otherID.uuidString))
 }
 suite.test("Platform.testInterruptedCalibrationCannotComplete") {
  let (m,s,_)=fixture(); m.beginCalibration(.near)
  for i in 0..<10 { s.send(sample(Double(i),-45)) }; try check(m.calibrationPhase == .near && m.calibrationSampleCount == 10); m.pause(); m.start(); m.advance(at:time(30))
  try check(!m.nearReady && m.calibrationPhase == nil && m.calibration == nil)
 }
}
