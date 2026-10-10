import Foundation
import Combine
import WatchSignalCore
public struct ChartSample: Identifiable { public let id=UUID(); public let sample: SignalSample; public let ema: Double? }
public struct DeviceRow: Identifiable { public let id: UUID; public var name: String; public var rssi: Int; public var lastSeen: Date }
@MainActor public final class DiagnosticModel: ObservableObject {
 @Published public private(set) var selectedID: UUID?
 @Published public private(set) var selectedName=""
 @Published public private(set) var devices: [DeviceRow]=[]
 @Published public private(set) var chartSamples: [ChartSample]=[]
 @Published public private(set) var snapshot=PresenceSnapshot(state:.uncalibrated)
 @Published public private(set) var events: [SimulationEvent]=[]
 @Published public private(set) var availability: ScannerAvailability = .unavailable
 @Published public private(set) var isRunning=false
 @Published public private(set) var requestedScanning=false
 @Published public var errorMessage: String?
 @Published public private(set) var calibration: Calibration?
 @Published public private(set) var calibrationPhase: CalibrationPhase?
 @Published public private(set) var calibrationProgress=0.0
 @Published public private(set) var calibrationSampleCount=0
 @Published public private(set) var nearReady=false
 @Published public private(set) var currentTime: Date
 public var droppedLogCount: Int { log.droppedCount }
 private let scanner: any SignalScanning, store: SelectionStore, now: () -> Date
 private var detector: PresenceDetector?, collector: CalibrationCollector?
 private var calibrationStarted: Date?, sleeping=false
 private var eventCursor=0, log=SessionLog()
 public init(scanner: any SignalScanning, store: SelectionStore, now: @escaping () -> Date = Date.init) {
  self.scanner=scanner;self.store=store;self.now=now;currentTime=now()
  if let saved=store.load() {
   selectedID=saved.deviceID;selectedName=saved.name;calibration=saved.calibration
   detector=PresenceDetector(deviceID:saved.deviceID,calibration:saved.calibration)
   collector=CalibrationCollector(deviceID:saved.deviceID);snapshot=detector!.snapshot
  }
  errorMessage=store.loadError
  scanner.onSample={ [weak self] s,n in self?.receive(s,name:n) }
  scanner.onAvailability={ [weak self] state in self?.updateAvailability(state) }
 }
 public func select(deviceID: UUID, name: String) {
  selectedID=deviceID;selectedName=name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "我的手表" : name
  calibration=nil;detector=PresenceDetector(deviceID:deviceID,calibration:nil)
  collector=CalibrationCollector(deviceID:deviceID); chartSamples=[];events=[];log=SessionLog();eventCursor=0
  cancelCalibration();snapshot=detector!.snapshot;persist()
 }
 public func start() {
  requestedScanning=true;resetTransient();isRunning=availability == .ready && !sleeping
  if !sleeping { scanner.start() }
 }
 public func pause() {
  requestedScanning=false;isRunning=false;scanner.stop();resetTransient()
 }
 private func updateAvailability(_ state: ScannerAvailability) {
  availability=state
  if state != .ready { isRunning=false;resetTransient() }
  else { isRunning=requestedScanning && !sleeping }
 }
 public func handleSleep() { sleeping=true;isRunning=false;scanner.stop();resetTransient() }
 public func handleWake() { sleeping=false;resetTransient();if requestedScanning { scanner.start();isRunning=availability == .ready } }
 private func resetTransient() {
  detector?.reset();eventCursor=0;chartSamples=[];snapshot=detector?.snapshot ?? PresenceSnapshot(state:.uncalibrated)
  cancelCalibration()
 }
 private func cancelCalibration() {
  calibrationPhase=nil;calibrationStarted=nil;calibrationProgress=0;calibrationSampleCount=0;nearReady=false
  if let selectedID { collector=CalibrationCollector(deviceID:selectedID) }
 }
 private func receive(_ sample: SignalSample, name: String?) {
  guard isRunning, availability == .ready, !sleeping, sample.isValid else { return }
  let displayName=name?.isEmpty == false ? name! : "未命名设备"
  if let i=devices.firstIndex(where:{$0.id == sample.deviceID}) { devices[i]=DeviceRow(id:sample.deviceID,name:displayName,rssi:sample.rssi,lastSeen:sample.timestamp) }
  else { devices.append(DeviceRow(id:sample.deviceID,name:displayName,rssi:sample.rssi,lastSeen:sample.timestamp)) }
  guard sample.deviceID == selectedID, let detector else { return }
  if let last=detector.snapshot.lastSample, sample.timestamp < last { return }
  collector?.ingest(sample);calibrationSampleCount=collector?.sampleCount ?? 0
  detector.ingest(sample);snapshot=detector.snapshot
  chartSamples.append(ChartSample(sample:sample,ema:snapshot.ema))
  chartSamples.removeAll { sample.timestamp.timeIntervalSince($0.sample.timestamp) > 120 }
  log.append(sample:sample,snapshot:snapshot);collectEvents()
 }
 public func advance(at: Date) {
  currentTime=at
  devices.removeAll { at.timeIntervalSince($0.lastSeen) > 120 && $0.id != selectedID }
  chartSamples.removeAll { at.timeIntervalSince($0.sample.timestamp) > 120 }
  guard isRunning, availability == .ready, !sleeping else { return }
  if let began=calibrationStarted {
   calibrationProgress=min(1,max(0,at.timeIntervalSince(began)/20))
   if at.timeIntervalSince(began) >= 20 {
    let finishing=calibrationPhase;calibrationPhase=nil;calibrationStarted=nil
    do {
     if let result=try collector?.finish(at:at) {
      calibration=result;nearReady=false;detector?.setCalibration(result);eventCursor=0;persist()
     } else { nearReady=finishing == .near }
    } catch { errorMessage=error.localizedDescription;nearReady=false }
   }
  }
  detector?.tick(at:at);snapshot=detector?.snapshot ?? PresenceSnapshot(state:.uncalibrated);collectEvents()
 }
 public func beginCalibration(_ phase: CalibrationPhase) {
  guard isRunning, selectedID != nil else { errorMessage="请先开始扫描并确认目标设备。";return }
  guard calibrationPhase == nil else { return }
  if phase == .far && !nearReady { errorMessage="请先完成工位采样。";return }
  if phase == .near {
   calibration=nil;nearReady=false
   if let selectedID { collector=CalibrationCollector(deviceID:selectedID) }
   persist()
  }
  detector?.setCalibration(nil);eventCursor=0;snapshot=detector?.snapshot ?? PresenceSnapshot(state:.uncalibrated)
  chartSamples=[];errorMessage=nil;calibrationPhase=phase;calibrationStarted=now();calibrationProgress=0;calibrationSampleCount=0
  collector?.start(phase:phase,at:calibrationStarted!)
 }
 private func collectEvents() {
  guard let detector else { return }
  for event in detector.events.dropFirst(eventCursor) { events.append(event);log.append(event:event) }
  eventCursor=detector.events.count
  if events.count > 500 { events.removeFirst(events.count-500) }
 }
 private func persist() {
  guard let selectedID else { return }
  do { try store.save(SavedSelection(deviceID:selectedID,name:selectedName,calibration:calibration)) }
  catch { errorMessage="无法保存设备设置：\(error.localizedDescription)" }
 }
 public func exportCSV() -> String {
  guard let selectedID else { return "" }
  return log.csv(deviceID:selectedID,name:selectedName,calibration:calibration)
 }
}
