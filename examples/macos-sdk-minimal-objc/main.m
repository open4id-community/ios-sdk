#import <AppKit/AppKit.h>

#import "AppDelegate.h"

/// Programmatic AppKit entry point (the ObjC twin of the Swift sibling's
/// `@main Open4IDMinimalApp`).
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setDelegate:[[AppDelegate alloc] init]];
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
