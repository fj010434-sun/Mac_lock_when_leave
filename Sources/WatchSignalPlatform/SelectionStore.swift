import Foundation
import WatchSignalCore
public struct SavedSelection: Codable {
 public let deviceID: UUID; public let name: String; public let calibration: Calibration?
 public init(deviceID: UUID, name: String, calibration: Calibration?) { self.deviceID=deviceID;self.name=name;self.calibration=calibration }
}
@MainActor public final class SelectionStore {
 private let url: URL
 public private(set) var loadError: String?
 public init(url: URL? = nil) {
  self.url=url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WatchSignal/selection.json")
 }
 public func load() -> SavedSelection? {
  loadError=nil
  guard FileManager.default.fileExists(atPath:url.path) else { return nil }
  do {
   let saved=try JSONDecoder().decode(SavedSelection.self,from:Data(contentsOf:url))
   if let c=saved.calibration, !c.isValid { throw CocoaError(.fileReadCorruptFile) }
   return saved
  } catch { loadError="无法读取已保存的设备设置：\(error.localizedDescription)"; return nil }
 }
 public func save(_ selection: SavedSelection?) throws {
  if let selection {
   try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
   let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
   try encoder.encode(selection).write(to:url,options:.atomic)
  } else if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
 }
}
