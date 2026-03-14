import AppKit
import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let transparencyRange: ClosedRange<Double> = 0.2...1.0
    static let defaultTaskStates = ["TODO", "DONE"]

    static func defaultOrgFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Ordo", isDirectory: true)
            .appendingPathComponent("main.org", isDirectory: false)
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            persistLaunchAtLogin()
        }
    }

    @Published var orgFilePath: String {
        didSet {
            guard orgFilePath != oldValue else { return }
            let normalized = Self.normalize(path: orgFilePath)
            if normalized != orgFilePath {
                orgFilePath = normalized
                return
            }
            defaults.set(orgFilePath, forKey: Keys.orgFilePath)
        }
    }

    @Published var inactiveTransparency: Double {
        didSet {
            let range = Self.transparencyRange
            if inactiveTransparency < range.lowerBound {
                inactiveTransparency = range.lowerBound
                return
            }
            if inactiveTransparency > range.upperBound {
                inactiveTransparency = range.upperBound
                return
            }
            guard inactiveTransparency != oldValue else { return }
            defaults.set(inactiveTransparency, forKey: Keys.inactiveTransparency)
        }
    }

    @Published var focusedTransparency: Double {
        didSet {
            let range = Self.transparencyRange
            if focusedTransparency < range.lowerBound {
                focusedTransparency = range.lowerBound
                return
            }
            if focusedTransparency > range.upperBound {
                focusedTransparency = range.upperBound
                return
            }
            guard focusedTransparency != oldValue else { return }
            defaults.set(focusedTransparency, forKey: Keys.focusedTransparency)
        }
    }

    @Published var taskStates: [String] {
        didSet {
            let sanitized = Self.sanitizeTaskStates(taskStates)
            if sanitized != taskStates {
                taskStates = sanitized
                return
            }
            defaults.set(taskStates, forKey: Keys.taskStates)
        }
    }

    var orgFileURL: URL {
        let expanded = (orgFilePath as NSString).expandingTildeInPath
        if expanded.isEmpty {
            return Self.defaultOrgFileURL()
        }
        return URL(fileURLWithPath: expanded, isDirectory: false)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let rawOrgPath = defaults.string(forKey: Keys.orgFilePath)
            ?? Self.defaultOrgFileURL().path
        orgFilePath = Self.normalize(path: rawOrgPath)

        let storedInactive = defaults.object(forKey: Keys.inactiveTransparency) as? Double
        inactiveTransparency = storedInactive ?? 0.32

        let storedFocused = defaults.object(forKey: Keys.focusedTransparency) as? Double
        focusedTransparency = storedFocused ?? 0.96

        if let storedLaunch = defaults.object(forKey: Keys.launchAtLogin) as? Bool {
            launchAtLogin = storedLaunch
        } else {
            launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        }

        if let storedStates = defaults.array(forKey: Keys.taskStates) as? [String], !storedStates.isEmpty {
            taskStates = Self.sanitizeTaskStates(storedStates)
        } else {
            taskStates = Self.defaultTaskStates
        }
    }

    func refreshLaunchAtLoginState() {
        let enabled = LaunchAtLoginManager.shared.isEnabled
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    func addTaskState() {
        var updated = taskStates
        updated.append("STATE")
        taskStates = updated
    }

    func removeTaskState(at index: Int) {
        guard taskStates.indices.contains(index), taskStates.count > 1 else { return }
        var updated = taskStates
        updated.remove(at: index)
        taskStates = updated
    }

    func updateTaskState(at index: Int, to newValue: String) {
        guard taskStates.indices.contains(index) else { return }
        var updated = taskStates
        updated[index] = newValue
        taskStates = updated
    }

    func moveTaskStates(from source: IndexSet, to destination: Int) {
        var updated = taskStates
        updated.move(fromOffsets: source, toOffset: destination)
        taskStates = updated
    }
}

private extension AppSettings {
    func persistLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.setEnabled(launchAtLogin)
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        } catch {
            NSLog("Ordo: launch-at-login update failed: \(error.localizedDescription)")
            refreshLaunchAtLoginState()
        }
    }

    static func normalize(path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeTaskStates(_ states: [String]) -> [String] {
        let normalized = states
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var result: [String] = []
        for state in normalized {
            if seen.insert(state).inserted {
                result.append(state)
            }
        }
        return result.isEmpty ? defaultTaskStates : result
    }

    struct Keys {
        static let orgFilePath = "settings.orgFilePath"
        static let launchAtLogin = "settings.launchAtLogin"
        static let inactiveTransparency = "settings.inactiveTransparency"
        static let focusedTransparency = "settings.focusedTransparency"
        static let taskStates = "settings.taskStates"
    }

}

enum LaunchAtLoginError: Error {
    case executableNotFound
}

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private let label = "com.nyushi.ordo.launcher"
    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    private init() {}

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installAgent()
        } else {
            try removeAgentIfNeeded()
        }
    }
}

private extension LaunchAtLoginManager {
    func installAgent() throws {
        try ensureParentDirectory()
        let programArguments = try resolveProgramArguments()
        let payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    func removeAgentIfNeeded() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: launchAgentURL.path) {
            try fm.removeItem(at: launchAgentURL)
        }
    }

    func ensureParentDirectory() throws {
        let directoryURL = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func resolveProgramArguments() throws -> [String] {
        let bundle = Bundle.main
        let bundlePath = bundle.bundleURL.path
        if bundlePath.hasSuffix(".app") {
            return ["/usr/bin/open", "-a", bundlePath]
        }
        if let executable = bundle.executableURL?.path {
            return [executable]
        }
        throw LaunchAtLoginError.executableNotFound
    }
}
