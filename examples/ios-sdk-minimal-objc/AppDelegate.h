#import <UIKit/UIKit.h>

@class Open4IDAuthClient;
@class Open4IDSocialClient;

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

/// The shared Open4ID client (base Swift class — Objective-C cannot
/// subclass it, so the Google seam is injected as a provider instead).
@property (strong, nonatomic, readonly) Open4IDAuthClient *authClient;

/// The Google code provider registered on `authClient` (see
/// `Open4IDGoogleAuthorizationCodeProviding`).
@property (strong, nonatomic, readonly) Open4IDSocialClient *socialClient;

@end

NS_ASSUME_NONNULL_END
