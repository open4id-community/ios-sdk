#import <Foundation/Foundation.h>
@import Open4IDSDK;

NS_ASSUME_NONNULL_BEGIN

/// Sample-only Google code provider mirroring the Android sample's
/// `SocialAuthClient`: interactive Google Sign-In only.
///
/// Objective-C cannot subclass Swift classes (the generated
/// `Open4IDAuthClient` interface carries `objc_subclassing_restricted`),
/// so instead of subclassing, this object implements
/// `Open4IDGoogleAuthorizationCodeProviding` and is registered on the
/// client with `setGoogleAuthorizationCodeProvider:`. The base SDK owns
/// GitHub and Apple (`ASWebAuthenticationSession` defaults) and reports
/// `provider_unavailable` for Google when no provider is registered.
///
/// This uses the Google Sign-In SDK (`GoogleSignIn-iOS` SPM package)
/// exactly like the Android sample uses `play-services-auth`: a forced
/// sign-out so the account picker always appears, then a presented
/// sign-in whose result carries a fresh server auth code.
///
/// Two Google client IDs are involved:
/// - `clientId` (passed to `getAuthorizationCode...`) = the bootstrap Web
///   client — the server-auth-code audience, exchanged server-side
///   through the empty-`redirect_uri` fallback (2026-10-12 server fix,
///   Android parity).
/// - `googleIosClientId` = the GCP **iOS-type** OAuth client bound to the
///   sample bundle ID (dev fixture), set via `setGoogleIosClientId:`.
@interface Open4IDSocialClient : NSObject <Open4IDGoogleAuthorizationCodeProviding>

/// The GCP iOS-type OAuth client ID. Empty keeps the base seam's
/// `provider_unavailable` behavior.
@property (nonatomic, copy, readonly) NSString *googleIosClientId;

- (void)setGoogleIosClientId:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
