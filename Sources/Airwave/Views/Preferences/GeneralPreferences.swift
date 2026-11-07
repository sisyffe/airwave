import ServiceManagement
import SwiftUI

/// General settings: app-level behaviour (launch at login, quitting) and how the
/// app looks (thumbnail display and the extra seek controls).
struct GeneralPreferences: View {
    @AppStorage(Prefs.quitOnLastWindowClosed) private var quitOnLastWindowClosed = Prefs.defaultQuitOnLastWindowClosed
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("App") {
                Toggle("Open Airwave at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {
                            launchAtLogin = !enabled
                        }
                    }
                    .help("Requires running Airwave as a bundled .app")
                Toggle("Quit when the last window closes", isOn: $quitOnLastWindowClosed)
                    .help(
                        "On: closing the last window quits Airwave. Off: Airwave stays running and audio continues, like a standard macOS app. Use ⌘Q to quit."
                    )
            }

            Section("Appearance") {
                AppearanceSettings()
            }
        }
        .formStyle(.grouped)
    }
}
