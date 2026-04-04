import AppKit
import SwiftUI

@main
struct OrdoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings

    init() {
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        NSLog("Ordo build \(bundleVersion) (\(buildVersion)) launched at \(Date())")
        let sharedSettings = AppSettings()
        _settings = StateObject(wrappedValue: sharedSettings)
        appDelegate.settings = sharedSettings
    }

    var body: some Scene {
        Settings {
            SettingsView(settings: settings)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var showRelaunchPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(title: "General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .help("Start Ordo automatically right after logging in.")
            }

            settingsSection(title: "Appearance") {
                transparencyRow(
                    title: "Focused",
                    value: $settings.focusedTransparency
                )
                transparencyRow(
                    title: "Inactive",
                    value: $settings.inactiveTransparency
                )
                Text("Adjust panel transparency when the pointer is over it vs. when inactive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsSection(title: "Task states") {
                VStack(alignment: .leading, spacing: 8) {
                    List {
                        ForEach(Array(settings.taskStates.enumerated()), id: \.offset) { index, _ in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                    .help("Drag to reorder")
                                TextField("State \(index + 1)", text: Binding(
                                    get: {
                                        guard settings.taskStates.indices.contains(index) else { return "" }
                                        return settings.taskStates[index]
                                    },
                                    set: { newValue in
                                        settings.updateTaskState(at: index, to: newValue)
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                if settings.taskStates.count > 1 {
                                    Button(role: .destructive) {
                                        settings.removeTaskState(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this state")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                        .onMove { indices, newOffset in
                            settings.moveTaskStates(from: indices, to: newOffset)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: max(CGFloat(settings.taskStates.count) * 36, 120))

                    Button("Add state") {
                        settings.addTaskState()
                    }
                    Text("States drive Ordo's inline picker and click-to-cycle behavior. They must match the text at the beginning of task lines. Drag the handle to reorder them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsSection(title: "Org file") {
                Text(settings.orgFileURL.path)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.2))
                    .cornerRadius(6)
                Button("Browse...") {
                    chooseOrgFile()
                }
                Text("Choose an existing org file or create a new one via Finder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 460)
        .alert("Relaunch required", isPresented: $showRelaunchPrompt) {
            Button("Relaunch Now") {
                RelaunchHelper.relaunch()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Restart Ordo to switch to the newly selected org file.")
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content)
        }
    }

    private func transparencyRow(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: AppSettings.transparencyRange)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func chooseOrgFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.directoryURL = settings.orgFileURL.deletingLastPathComponent()
        let previousPath = settings.orgFileURL.path
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard url.path != previousPath else { return }
            settings.orgFilePath = url.path
            DispatchQueue.main.async {
                showRelaunchPrompt = true
            }
        }
    }

}
