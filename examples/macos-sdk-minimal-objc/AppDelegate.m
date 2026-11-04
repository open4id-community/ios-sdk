#import "AppDelegate.h"

// The SDK is consumed as a local source Swift package, so ObjC imports the
// Swift module directly (`@import`), like `examples/ios-sdk-minimal-objc`
// does (see ViewController.m for the xcframework note).
@import Open4IDSDK;

#import "ViewController.h"

@interface AppDelegate ()

@property (strong, nonatomic) Open4IDAuthClient *client;
@property (strong, nonatomic) NSWindow *window;

@end

@implementation AppDelegate

- (instancetype)init {
    if ((self = [super init])) {
        // `[[Open4IDAuthClient alloc] init]` is the same construction the
        // Swift sibling's `let appClient = Open4IDAuthClient()` compiles to.
        _client = [[Open4IDAuthClient alloc] init];
    }
    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    // A minimal menu so the app quits with Cmd-Q like the SwiftUI sibling.
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Open4ID IAP"];
    NSString *quitTitle = [NSString stringWithFormat:@"Quit %@",
        @"Open4ID IAP (ObjC)"];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];
    NSApp.mainMenu = [[NSMenu alloc] init];
    [NSApp.mainMenu addItem:appMenuItem];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect frame = NSMakeRect(0, 0, 720, 600);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                          | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"Open4ID IAP (macOS, ObjC)";
    self.window.contentViewController =
        [[ViewController alloc] initWithNibName:nil bundle:nil];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
