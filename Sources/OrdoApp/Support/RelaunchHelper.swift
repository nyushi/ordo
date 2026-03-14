import AppKit
import Foundation

@MainActor
enum RelaunchHelper {
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["open", bundleURL.path]
            try? task.run()
        } else if let executableURL = Bundle.main.executableURL {
            let task = Process()
            task.executableURL = executableURL
            task.arguments = []
            try? task.run()
        }
        NSApp.terminate(nil)
    }
}
