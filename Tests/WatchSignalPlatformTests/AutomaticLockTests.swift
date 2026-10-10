import Foundation
import WatchSignalCore
import WatchSignalPlatform

// The OS key event is the external side effect; the real model, detector and log run here.
@MainActor final class RecordingLocker: ScreenLocking {
 var isAuthorized = true
 var requests = 0
 var fail = false
 func requestAuthorization() {}
 func lock() throws {
  requests += 1
  if fail { throw TestFailure(message:"OS lock request failed") }
 }
}

@MainActor func lockingFixture(_ locker: RecordingLocker) throws -> (DiagnosticModel, FakeScanner) {
 let scanner = FakeScanner()
 let store = SelectionStore(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("selection.json"))
 try store.save(SavedSelection(deviceID:targetID,name:"Test watch",calibration:calibration()))
 let model = DiagnosticModel(scanner:scanner,store:store,locker:locker,now:{time(0)})
 model.start()
 return (model,scanner)
}

@MainActor func registerAutomaticLockTests(_ suite: TestSuite) {
 suite.test("Sleep.testDirectSystemSleepNeedsNoEventPermissionAndUsesSleepnow") {
  var commands: [String]=[];var completed=false
  let sleeper=SystemSleeper(run:{ url,args,completion in
   commands=[url.path]+args;completion(.success(()))
  })
  sleeper.onSleepResult={ if case .success = $0 { completed=true } }
  try check(sleeper.isAuthorized)
  try sleeper.lock()
  try check(commands == ["/usr/bin/pmset","sleepnow"] && completed)
 }
 suite.test("Sleep.testLaunchFailureThrowsAndCommandFailureIsReported") {
  let unavailable=SystemSleeper(run:{ _,_,_ in throw TestFailure(message:"launch failed") })
  try expectThrow { try unavailable.lock() }
  var failed=false
  let sleeper=SystemSleeper(run:{ _,_,completion in completion(.failure(TestFailure(message:"sleep rejected"))) })
  sleeper.onSleepResult={ if case .failure = $0 { failed=true } }
  try sleeper.lock();try check(failed)
 }
 suite.test("Sleep.testActualProcessRunnerReportsExitWithoutSleepingTestMachine") {
  var outcomes: [Bool]=[]
  for command in ["/usr/bin/true","/usr/bin/false"] {
   try SystemSleeper.runCommand(URL(fileURLWithPath:command),[]) { outcome in
    switch outcome { case .success: outcomes.append(true);case .failure: outcomes.append(false) }
   }
   for _ in 0..<100 where outcomes.count < (command.hasSuffix("true") ? 1 : 2) {
    try await Task.sleep(for:.milliseconds(10))
   }
  }
  try check(outcomes == [true,false])
 }
 suite.test("Sleep.testModelLogsFailureDisablesAndRetainsCalibrationAcrossWake") {
  let (model,scanner)=try lockingFixture(RecordingLocker())
  let saved=model.calibration
  model.setAutomaticLock(true)
  model.recordSystemSleep(.failure(SystemSleepError.commandFailed(1)))
  try check(!model.automaticLockEnabled && model.errorMessage != nil)
  try check(model.exportCSV().contains("systemSleepRequest,systemSleep") && model.lockAttempts.last?.result == .failed)
  model.handleSleep();model.handleWake()
  try check(model.calibration == saved && model.snapshot.state == .warmingUp)
  model.setAutomaticLock(true)
  for i in 0..<5 { scanner.send(sample(Double(i),-45)) }
  try check(model.snapshot.state == .present)
 }
 suite.test("Lock.testSystemSequenceLocksImmediatelyThenSleepsDisplay") {
  var steps: [String]=[];var result: LockResult?
  let locker=SystemScreenLocker(authorized:{true},postShortcut:{steps.append("lock")},sleepDisplay:{steps.append("sleep")})
  locker.onDisplaySleepResult={ outcome in
   switch outcome { case .success: result = .requested;case .failure: result = .failed }
  }
  try locker.lock();try check(steps == ["lock"], "lock request must be immediate; display sleep follows")
  try await Task.sleep(for:.milliseconds(1000))
  try check(steps == ["lock","sleep"] && result == .requested)
 }
 suite.test("Lock.testSystemSequenceDoesNotSleepWhenLockCannotBeRequested") {
  for granted in [false,true] {
   var steps: [String]=[]
   let locker=SystemScreenLocker(authorized:{granted},postShortcut:{steps.append("lock");throw TestFailure(message:"key dispatch failed")},sleepDisplay:{steps.append("sleep")})
   try expectThrow { try locker.lock() }
   try await Task.sleep(for:.milliseconds(1000))
   try check(!steps.contains("sleep"))
  }
 }
 suite.test("Lock.testDisplaySleepFailureIsReportedAfterLockRequest") {
  var steps: [String]=[];var failed=false
  let locker=SystemScreenLocker(authorized:{true},postShortcut:{steps.append("lock")},sleepDisplay:{steps.append("sleep");throw TestFailure(message:"pmset failed")})
  locker.onDisplaySleepResult={ if case .failure = $0 { failed=true } }
  try locker.lock();try await Task.sleep(for:.milliseconds(1000))
  try check(steps == ["lock","sleep"] && failed)
 }
 suite.test("Lock.testWeakDepartureLocksInSameCallExactlyOnceAndRearmsOnReturn") {
  let locker=RecordingLocker();let (m,s)=try lockingFixture(locker)
  m.setAutomaticLock(true)
  for i in 0..<5 { s.send(sample(Double(i),-45)) }
  for i in 5...14 { s.send(sample(Double(i),-65)) }
  try check(locker.requests == 0)
  s.send(sample(15,-65))
  try check(locker.requests == 1 && m.lockAttempts.count == 1, "departure must request lock before receive returns")
  for i in 16...20 { s.send(sample(Double(i),-65));m.advance(at:time(Double(i))) }
  try check(locker.requests == 1, "same departure must not repeatedly lock")
  for i in 21...30 { s.send(sample(Double(i),-20)) }
  for i in 31...45 { s.send(sample(Double(i),-65)) }
  try check(locker.requests == 2, "a new departure after return must lock again")
  try check(m.exportCSV().contains("lockRequest") && m.exportCSV().contains("requested"))
 }
 suite.test("Lock.testMissingSignalLocksAtTwentySecondsOnlyOnce") {
  let locker=RecordingLocker();let (m,s)=try lockingFixture(locker);m.setAutomaticLock(true)
  for i in 0..<5 { s.send(sample(Double(i),-45)) }
  m.advance(at:time(23.99));try check(locker.requests == 0)
  m.advance(at:time(24));try check(locker.requests == 1)
  m.advance(at:time(60));try check(locker.requests == 1)
 }
 suite.test("Lock.testDisabledModeAndOtherWatchNeverLock") {
  let locker=RecordingLocker();let (m,s)=try lockingFixture(locker)
  for i in 0..<5 { s.send(sample(Double(i),-45)) }
  for i in 5...20 { s.send(sample(Double(i),-65)) }
  try check(locker.requests == 0 && m.lockAttempts.isEmpty)
  m.setAutomaticLock(true)
  s.send(sample(30,-45,otherID));m.advance(at:time(100))
  try check(locker.requests == 0, "enabling must not replay an old departure or use another device")
 }
 suite.test("Lock.testUnavailablePauseAndCalibrationSuppressLockRequests") {
  for mode in 0..<3 {
   let locker=RecordingLocker();let (m,s)=try lockingFixture(locker);m.setAutomaticLock(true)
   for i in 0..<5 { s.send(sample(Double(i),-45)) }
   if mode == 0 { m.pause() }
   if mode == 1 { s.onAvailability?(.poweredOff) }
   if mode == 2 { m.beginCalibration(.near) }
   m.advance(at:time(100));try check(locker.requests == 0)
  }
 }
 suite.test("Lock.testPermissionDeniedAndRevokedDoNotSendKeys") {
  let locker=RecordingLocker();locker.isAuthorized=false
  let (m,s)=try lockingFixture(locker);m.setAutomaticLock(true)
  try check(!m.automaticLockEnabled && m.errorMessage != nil)
  m.lockNow();try check(locker.requests == 0 && m.lockAttempts.last?.result == .failed)
  locker.isAuthorized=true;m.setAutomaticLock(true)
  for i in 0..<5 { s.send(sample(Double(i),-45)) }
  locker.isAuthorized=false;m.advance(at:time(24))
  try check(locker.requests == 0 && !m.automaticLockEnabled && m.errorMessage != nil)
 }
 suite.test("Lock.testExecutionFailureIsVisibleLoggedAndNotRetriedInLoop") {
  let locker=RecordingLocker();locker.fail=true
  let (m,s)=try lockingFixture(locker);m.setAutomaticLock(true)
  for i in 0..<5 { s.send(sample(Double(i),-45)) }
  m.advance(at:time(24));m.advance(at:time(25))
  try check(locker.requests == 1 && m.lockAttempts.last?.result == .failed)
  try check(m.errorMessage != nil && m.exportCSV().contains("failed"))
 }
 suite.test("Lock.testManualRequestWorksWithoutCalibrationAndIsLogged") {
  let locker=RecordingLocker();let scanner=FakeScanner()
  let m=DiagnosticModel(scanner:scanner,store:SelectionStore(),locker:locker,now:{time(10)})
  m.lockNow()
  try check(locker.requests == 1 && m.lockAttempts.last?.trigger == .manual)
 }
}
