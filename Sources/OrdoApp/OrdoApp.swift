import SwiftUI

@main
struct OrdoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ordo")
                .font(.title2)
            Text("常駐するテキスト Todo パネル。org ファイルを直接編集するミニマルなツールです。")
                .font(.body)
        }
        .padding()
        .frame(width: 320)
    }
}
