#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "Open4IDSocialClient.h"
@import Open4IDSDK;
@import AuthenticationServices;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // The window is created by SceneDelegate (scene lifecycle adoption).

    // Register the Google code provider (ObjC hosts cannot subclass the
    // Swift client — this is the injection seam).
    [self.authClient setGoogleAuthorizationCodeProvider:self.socialClient];

    // Wire the GitHub/Apple web sessions to present from the key window.
    __weak typeof(self) weakSelf = self;
    [self.authClient setPresentationAnchor:^ASPresentationAnchor {
        return [weakSelf keyWindow] ?: weakSelf.window;
    }];

    return YES;
}

// Scene configuration: the class name comes from the application scene
// manifest ("Default" configuration). Implementing this keeps UIKit and
// the manifest in sync.
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config =
        [[UISceneConfiguration alloc] initWithName:@"Default"
                                       sessionRole:connectingSceneSession.role];
    config.delegateClass = [SceneDelegate class];
    return config;
}

- (Open4IDAuthClient *)authClient {
    static Open4IDAuthClient *sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedClient = [[Open4IDAuthClient alloc] init];
    });
    return sharedClient;
}

- (Open4IDSocialClient *)socialClient {
    static Open4IDSocialClient *sharedSocial = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSocial = [[Open4IDSocialClient alloc] init];
    });
    return sharedSocial;
}

/// First key window across the foreground scenes (iOS 15+ path), falling
/// back to the app delegate window.
- (UIWindow *)keyWindow {
    UIWindow *found = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            found = ((UIWindowScene *)scene).keyWindow;
            if (found) break;
        }
    }
    return found;
}

@end
