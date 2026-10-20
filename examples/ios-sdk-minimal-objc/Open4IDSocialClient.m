#import "Open4IDSocialClient.h"
#import <GoogleSignIn/GoogleSignIn.h>
#import <UIKit/UIKit.h>

@implementation Open4IDSocialClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _googleIosClientId = @"";
    }
    return self;
}

- (void)setGoogleIosClientId:(NSString *)value {
    _googleIosClientId = [value stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
}

/// Registered implementation of `Open4IDGoogleAuthorizationCodeProviding`.
/// Maps GIDSignIn outcomes to SDK-stable error keys:
/// user cancel -> `client.auth.popup_closed`, failure / missing code ->
/// `client.auth.access_denied`, stale session -> `client.auth.popup_timeout`.
- (void)getAuthorizationCodeWithClientId:(NSString *)clientId
                                timeoutMs:(NSInteger)timeoutMs
                               completion:(void (^)(NSString * _Nullable,
                                                    NSError * _Nullable))completion {
    if (self.googleIosClientId.length == 0) {
        completion(nil, [NSError errorWithDomain:@"Open4IDSDK"
                                            code:100003
                                        userInfo:@{
            @"key": @"client.auth.provider_unavailable",
            @"field_errors": @{@"google_ios_client_id": @"required"},
        }]);
        return;
    }

    // First key window across foreground scenes, then topmost VC.
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            keyWindow = ((UIWindowScene *)scene).keyWindow;
            if (keyWindow) break;
        }
    }
    UIViewController *presenting = keyWindow.rootViewController;
    while (presenting.presentedViewController) {
        presenting = presenting.presentedViewController;
    }

    // Best-effort sign-out so the account picker always appears (Android parity).
    [GIDSignIn.sharedInstance signOut];
    GIDConfiguration *configuration =
        [[GIDConfiguration alloc] initWithClientID:self.googleIosClientId
                                    serverClientID:clientId];
    GIDSignIn.sharedInstance.configuration = configuration;

    __block BOOL settled = NO;
    // 120 s interaction budget (mirrors Open4IDAuthClient.GOOGLE_TIMEOUT_MS,
    // which is not exposed to ObjC).
    int64_t budgetMs = timeoutMs > 0 ? timeoutMs : 120000;

    [GIDSignIn.sharedInstance
        signInWithPresentingViewController:presenting
                                completion:^(GIDSignInResult * _Nullable result,
                                             NSError * _Nullable error) {
        if (settled) return;
        settled = YES;

        if (error) {
            // User cancel -> popup_closed (GIDSignInErrorCode canceled = -5).
            NSString *key = (error.code == -5)
                ? @"client.auth.popup_closed"
                : @"client.auth.access_denied";
            completion(nil, [NSError errorWithDomain:@"Open4IDSDK"
                                                code:100003
                                            userInfo:@{
                @"key": key,
                @"reason": @"google_sign_in_failed",
                @"gid_domain": error.domain ?: @"",
                @"gid_code": @(error.code),
            }]);
            return;
        }
        if (result.serverAuthCode.length == 0) {
            completion(nil, [NSError errorWithDomain:@"Open4IDSDK"
                                                code:100003
                                            userInfo:@{@"key": @"client.auth.access_denied"}]);
            return;
        }
        completion(result.serverAuthCode, nil);
    }];

    // Interaction budget (the base Google seam's timeout semantics).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, budgetMs * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (settled) return;
        settled = YES;
        completion(nil, [NSError errorWithDomain:@"Open4IDSDK"
                                            code:100003
                                        userInfo:@{@"key": @"client.auth.popup_timeout"}]);
    });
}

@end
