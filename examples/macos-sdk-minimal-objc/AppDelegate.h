#import <AppKit/AppKit.h>

@class Open4IDAuthClient;

NS_ASSUME_NONNULL_BEGIN

/// Owns the sample's shared `Open4IDAuthClient` and the app window. The
/// client holder mirrors `examples/ios-sdk-minimal-objc/AppDelegate` (the
/// established ObjC pattern in this repo); the Swift sibling uses a global
/// `appClient` instead.
@interface AppDelegate : NSObject <NSApplicationDelegate>

/// The sample's shared Open4ID client. This example exercises only the App
/// Store IAP path, so it uses the base client with no social/browser
/// overrides. Created once, re-configured by every action.
@property (strong, readonly, nonatomic) Open4IDAuthClient *client;

@end

NS_ASSUME_NONNULL_END
