import Foundation
import WatchSignalCore
struct TestFailure: Error { let message: String }
@MainActor final class TestSuite {
 var cases: [(String, @MainActor () throws -> Void)] = []
 func test(_ name: String, _ run: @escaping @MainActor () throws -> Void) { cases.append((name, run)) }
}
func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "assertion failed", file: String = #filePath, line: Int = #line) throws {
 if try !condition() { throw TestFailure(message: "\(file):\(line): \(message)") }
}
func expectThrow(_ body: () throws -> Void) throws {
 var didThrow = false
 do { try body() } catch { didThrow = true }
 try check(didThrow, "expected failure")
}
@main struct Runner {
 @MainActor static func main() {
  let suite = TestSuite()
  registerCalibrationTests(suite); registerPresenceTests(suite); registerLogTests(suite); registerPlatformTests(suite)
  let filter = CommandLine.arguments.dropFirst().first
  var failures = 0, count = 0
  for (name, run) in suite.cases where filter == nil || name.contains(filter!) {
   count += 1
   do { try run(); print("PASS \(name)") } catch { failures += 1; print("FAIL \(name): \(error)") }
  }
  print("Tests: \(count), failures: \(failures)")
  if count == 0 || failures > 0 { exit(1) }
 }
}
