import SwiftUI
import ServiceManagement

/// General settings: hotstart, quit-on-close behavior and launch at login.
struct GeneralPreferences: View {
    @AppStorage(Prefs.hotstart) private var hotstart = true
    @AppStorage(Prefs.quitOnLastWindowClosed) private var quitOnLastWindowClosed = Prefs.defaultQuitOnLastWindowClosed
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Hotstart: play automatically when Airwave opens", isOn: $hotstart)
                .help("Resumes the last played source")
            Toggle("Quit when the last window closes", isOn: $quitOnLastWindowClosed)
                .help(
                    "On: closing the last window quits Airwave. Off: Airwave stays running and audio continues, like a standard macOS app. Use ⌘Q to quit."
                )
            Toggle("Open Airwave at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {
                        launchAtLogin = !enabled
                    }
                }
                .help("Requires running Airwave as a bundled .app")
        }
        .formStyle(.grouped)
    }
}
