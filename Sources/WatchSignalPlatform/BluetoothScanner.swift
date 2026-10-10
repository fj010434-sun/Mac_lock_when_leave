import Foundation
import WatchSignalCore
public enum ScannerAvailability: Equatable, Sendable { case ready, unauthorized, poweredOff, unsupported, unavailable }
@MainActor public protocol SignalScanning: AnyObject {
 var onSample: ((SignalSample, String?) -> Void)? { get set }
 var onAvailability: ((ScannerAvailability) -> Void)? { get set }
 func start(); func stop()
}
import CoreBluetooth
@MainActor public final class BluetoothScanner: NSObject, SignalScanning, @preconcurrency CBCentralManagerDelegate {
 public var onSample: ((SignalSample, String?) -> Void)?
 public var onAvailability: ((ScannerAvailability) -> Void)?
 private var manager: CBCentralManager?
 private var wantsScanning=false
 public override init() { super.init() }
 public func start() {
  wantsScanning=true
  if manager == nil { manager=CBCentralManager(delegate:self,queue:.main) }
  else { beginIfReady() }
 }
 public func stop() { wantsScanning=false; manager?.stopScan() }
 private func beginIfReady() {
  guard wantsScanning, let manager, manager.state == .poweredOn, !manager.isScanning else { return }
  manager.scanForPeripherals(withServices:nil,options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])
 }
 public func centralManagerDidUpdateState(_ central: CBCentralManager) {
  let state: ScannerAvailability
  switch central.state {
  case .poweredOn: state = .ready
  case .poweredOff: state = .poweredOff
  case .unauthorized: state = .unauthorized
  case .unsupported: state = .unsupported
  default: state = .unavailable
  }
  onAvailability?(state)
  if state == .ready { beginIfReady() }
 }
 public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String:Any], rssi RSSI: NSNumber) {
  guard wantsScanning, central.state == .poweredOn else { return }
  let name=advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
  onSample?(SignalSample(deviceID:peripheral.identifier,timestamp:Date(),rssi:RSSI.intValue),name)
 }
}
