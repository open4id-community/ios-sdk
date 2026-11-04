#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Main window controller. Mirrors `examples/macos-sdk-minimal/ContentView.swift`
/// in pure Objective-C: configuration fields, bootstrap, payments actions,
/// and an append-only log console. Every SDK call goes through the `@objc`
/// completion-handler surface (`configure…error:`, `bootstrap:`,
/// `products`, `verifyTransaction:completion:`, `verifyConsumable:completion:`,
/// `restore:`, `refresh:`).
@interface ViewController : NSViewController

@end

NS_ASSUME_NONNULL_END
