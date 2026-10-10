import Foundation
public final class PresenceDetector {
 private let deviceID: UUID
 private var calibration: Calibration?
 private var count=0, established=false, isAway=false, missingNotified=false
 private var weakSince: Date?, returnSince: Date?
 public private(set) var snapshot: PresenceSnapshot
 public private(set) var events: [SimulationEvent] = []
 public init(deviceID: UUID, calibration: Calibration?) {
  self.deviceID=deviceID; self.calibration=calibration?.isValid == true ? calibration : nil
  snapshot=PresenceSnapshot(state: self.calibration == nil ? .uncalibrated : .warmingUp)
 }
 public func reset() {
  count=0; established=false; isAway=false; missingNotified=false; weakSince=nil; returnSince=nil
  snapshot=PresenceSnapshot(state: calibration == nil ? .uncalibrated : .warmingUp)
  events=[]
 }
 public func setCalibration(_ calibration: Calibration?) {
  self.calibration=calibration?.isValid == true ? calibration : nil; reset()
 }
 public func ingest(_ sample: SignalSample) {
  guard sample.deviceID == deviceID, sample.isValid else { return }
  if let last=snapshot.lastSample {
   let gap=sample.timestamp.timeIntervalSince(last)
   guard gap >= 0 else { return }
   if gap >= 20 || snapshot.state == .awayMissing {
    let history=events; reset(); events=history
   } else if gap > 5 { weakSince=nil; returnSince=nil }
  }
  snapshot.ema = snapshot.ema.map { $0 * 0.75 + Double(sample.rssi) * 0.25 } ?? Double(sample.rssi)
  snapshot.lastSample=sample.timestamp; count += 1
  tick(at: sample.timestamp)
 }
 public func tick(at: Date) {
  guard let calibration else { snapshot.state = .uncalibrated; return }
  guard let last=snapshot.lastSample, let ema=snapshot.ema else { snapshot.state = .warmingUp; return }
  let age=at.timeIntervalSince(last)
  guard age >= 0 else { return }
  if age > 5 {
   weakSince=nil; returnSince=nil
   if established && age >= 20 {
    snapshot.state = .awayMissing
    if !missingNotified {
     if !isAway { events.append(SimulationEvent(timestamp: at, reason: .missingSignal)) }
     missingNotified=true; isAway=true
    }
   } else { snapshot.state = .stale }
   return
  }
  guard count >= 5 else { snapshot.state = .warmingUp; return }
  if !established {
   guard ema >= calibration.returnThreshold else { snapshot.state = .warmingUp; return }
   established=true
  }
  if isAway {
   if ema >= calibration.returnThreshold {
    if returnSince == nil { returnSince=at }
    if at.timeIntervalSince(returnSince!) >= 3 {
     isAway=false; missingNotified=false; returnSince=nil; weakSince=nil; snapshot.state = .returned
    } else { snapshot.state = .pendingReturn }
   } else { returnSince=nil; snapshot.state = .awayWeak }
  } else if ema < calibration.awayThreshold {
   if weakSince == nil { weakSince=at }
   if at.timeIntervalSince(weakSince!) >= 8 {
    isAway=true; snapshot.state = .awayWeak; events.append(SimulationEvent(timestamp: at, reason: .weakSignal))
   } else { snapshot.state = .pendingAway }
  } else {
   weakSince=nil
   if snapshot.state != .returned { snapshot.state = .present }
  }
 }
}
