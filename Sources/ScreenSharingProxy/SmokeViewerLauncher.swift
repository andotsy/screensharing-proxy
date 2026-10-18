import ProxyAppSupport

/// The explicit CI smoke mode checks the app-owned relay without opening a
/// connection to another computer or prompting for credentials.
struct SmokeViewerLauncher: ViewerLaunching {
    nonisolated func open(port: UInt16) async -> Bool { true }
}
