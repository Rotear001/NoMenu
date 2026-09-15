// Run from the project root:
// xcrun swift -module-cache-path .module-cache Tests/run-settings-checks.swift
// Uses real source in the Swift interpreter, isolated defaults/login adapters,
// and hidden-window rendering. This does NOT replace signed-app/TCC testing.
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sources = root.appendingPathComponent("Sources/NoMenu")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("nomenu-settings-checks-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
let files = enumerator.compactMap { $0 as? URL }
    .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "NoMenuApp.swift" }
    .sorted { $0.path < $1.path }
let test = root.appendingPathComponent("Tests/" + (CommandLine.arguments.dropFirst().first ?? "SettingsContentChecks.swift"))
let combined = try (files + [test]).map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
let main = temporary.appendingPathComponent("main.swift")
try combined.write(to: main, atomically: true, encoding: .utf8)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
task.currentDirectoryURL = root
task.arguments = ["swift", "-swift-version", "6", "-sdk",
                  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk",
                  "-module-cache-path", root.appendingPathComponent(".module-cache").path, main.path]
var environment = ProcessInfo.processInfo.environment
environment["NOMENU_SETTINGS_SNAPSHOT_DIR"] = temporary.path
environment["NOMENU_TEST_ICON"] = root.appendingPathComponent("Resources/NoMenu.icns").path
task.environment = environment
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
