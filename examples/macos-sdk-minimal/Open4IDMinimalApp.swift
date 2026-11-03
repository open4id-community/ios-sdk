import SwiftUI
import Open4IDSDK

@main
struct Open4IDMinimalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// The sample's shared Open4ID client. This example exercises only the App
/// Store IAP path, so it uses the base client with no social/browser overrides.
let appClient: Open4IDAuthClient = Open4IDAuthClient()
