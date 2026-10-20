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

/// The sample's shared Open4ID client: the Google-sign-in subclass, so the
/// account picker seam is wired exactly like the Android sample's
/// `SocialAuthClient` (GitHub/Apple stay on the base SDK's web-session
/// defaults; Google's iOS client ID arrives from the config fields).
let appClient: Open4IDAuthClient = Open4IDSocialClient()
