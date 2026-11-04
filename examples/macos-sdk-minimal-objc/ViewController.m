#import "ViewController.h"
#import "AppDelegate.h"

// The SDK is consumed as a local source Swift package, so ObjC imports the
// Swift module directly (`@import`), like `examples/ios-sdk-minimal-objc`
// does. (`@import` needs the package's Clang module, which a source build
// provides; the remote binary xcframework instead ships
// `Open4IDSDK-Swift.h` for `#import`.)
@import Open4IDSDK;
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

/// `OPEN4ID_<name>` launch-environment override with a fixture default, so a
/// local-stack or alternate-app run needs no source edit. Set values in the
/// scheme's Run → Arguments → Environment Variables (same hook as the Swift
/// sibling).
static NSString *EnvDefault(NSString *name, NSString *fallback) {
    NSString *key = [@"OPEN4ID_" stringByAppendingString:name];
    NSString *value = [NSProcessInfo.processInfo.environment objectForKey:key];
    return value.length ? value : fallback;
}

/// Typed-error detail for the log console: stable key (in
/// `NSLocalizedDescriptionKey` / `userInfo[@"key"]`) plus field errors, so a
/// failure names its exact gate. The proof value never reaches the string.
static NSString *DescribeError(NSError *error) {
    NSString *text = error.localizedDescription;
    id rawFields = [error.userInfo objectForKey:@"field_errors"];
    if ([rawFields isKindOfClass:[NSDictionary class]] &&
        [(NSDictionary *)rawFields count] > 0) {
        return [NSString stringWithFormat:@"%@ %@", text,
                (NSDictionary *)rawFields];
    }
    return text.length ? text : @"unknown error";
}

/// The SDK's `@objc` completion twins may fire on a background executor, so
/// every completion body hops to the main queue before touching AppKit.
static void OnMain(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

/// Minimal **macOS App Store IAP test harness for the Open4ID SDK, in pure
/// Objective-C** (the ObjC twin of `examples/macos-sdk-minimal/ContentView.swift`).
///
/// Scope is deliberately narrow: **payments only, no login UI**. The payment
/// feature lives in the SDK — `client.storeKitPayments` loads the shop rows
/// from the Open4ID catalog request and runs the StoreKit 2 purchase pipeline
/// (sheet → JWS proof → verify → finish) — while **the shop UI stays
/// host-owned**: this sample renders its own Buy buttons from the
/// `Open4IDStoreProduct` rows the SDK returns, the same way a game would.
/// There is no shop view in the SDK on purpose, and the sample is pure
/// Objective-C with **zero Swift files**: StoreKit 2 is a Swift-only API, and
/// the SDK owns that side.
///
/// There is no social/provider/browser flow here, so no
/// `ASWebAuthenticationSession` anchor, URL-scheme callback, or Portal origin
/// is needed. The SDK still requires a `redirectUri` at `configure` time; it
/// is a placeholder that the IAP path never uses. A purchase that has no
/// session signs in as a guest automatically, which requires guest login to
/// be enabled for the application.
///
/// There is no social/provider/browser flow here, so no
/// `ASWebAuthenticationSession` anchor, URL-scheme callback, or Portal origin
/// is needed. The SDK still requires a `redirectUri` at `configure` time; it
/// is a placeholder that the IAP path never uses. A purchase that has no
/// session signs in as a guest automatically, which requires guest login to
/// be enabled for the application.
@interface ViewController ()

// MARK: Configuration fields

@property (strong, nonatomic) NSTextField *appIdField;
@property (strong, nonatomic) NSTextField *environmentField;
@property (strong, nonatomic) NSTextField *publicSdkKeyField;
@property (strong, nonatomic) NSTextField *endpointField;
@property (strong, nonatomic) NSTextField *bundleIdField;
@property (strong, nonatomic) NSTextField *redirectUriField;

// MARK: State + log

@property (strong, nonatomic) NSTextField *bootstrapValue;
@property (strong, nonatomic) NSMutableArray<NSString *> *logLines;
@property (strong, nonatomic) NSTextView *logView;
@property (strong, nonatomic) os_log_t console;

/// One at a time, like the Swift sibling's `busy` flag; the action buttons
/// are disabled while an action runs.
@property (assign, nonatomic) BOOL busy;
@property (strong, nonatomic) NSMutableArray<NSButton *> *actionButtons;

// MARK: Payments (App Store)

/// Shop rows from the SDK's built-in store: the `app_store` catalog rows
/// joined with the StoreKit products (name/price). The sample renders one
/// Buy button per row; the SDK owns everything behind the button. There is
/// no shop view in the SDK on purpose — the shop UI stays host-owned.
@property (strong, nonatomic) NSArray<Open4IDStoreProduct *> *shopRows;
/// Buy button tag → shop row.
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, Open4IDStoreProduct *> *rowsByTag;
/// The SDK's built-in StoreKit store namespace, cached once (stable for the
/// client's lifetime, like the payments/entitlements namespaces).
@property (strong, nonatomic) Open4IDStoreKitPayments *store;
@property (strong, nonatomic) NSStackView *buyButtonsStack;
/// SDK namespaces, cached once. The payments namespace object is stable for
/// the client's lifetime.
@property (strong, nonatomic) Open4IDPayments *payments;
@property (strong, nonatomic) Open4IDEntitlements *entitlements;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.logLines = [NSMutableArray array];
    self.actionButtons = [NSMutableArray array];
    self.shopRows = @[];
    self.rowsByTag = [NSMutableDictionary dictionary];
    self.console = os_log_create("com.open4id.example.macos", "iap");
    [self buildUI];
    [self applyEnvironmentDefaults];
    [self append:@"[open4id-iap] Ready (macOS, ObjC)."];
    // Auto configure + bootstrap on launch so a launch proves the live path
    // in the console without tapping anything (mirrors the sibling's
    // `.onAppear` block).
    [self autoBootstrap];
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)NSApp.delegate;
}

// MARK: - Environment overrides

- (void)applyEnvironmentDefaults {
    self.appIdField.stringValue = EnvDefault(@"APP_ID",
        @"app_4a17c6406abaefdf0d9a705e7175b37c");
    self.environmentField.stringValue = EnvDefault(@"ENVIRONMENT", @"development");
    // The public SDK key must allow the `macos` platform (Portal → SDK keys).
    self.publicSdkKeyField.stringValue = EnvDefault(@"SDK_KEY",
        @"sdk_pk_1c91d1ee8bcf04e9226c09f291bd18c21ceeaa6f61b34203");
    self.endpointField.stringValue = EnvDefault(@"ENDPOINT",
        @"https://id.open4id.com/api");
    // Override with OPEN4ID_ENDPOINT (or the field) to verify against a
    // different Open4ID deployment.
    // Required by `configure`; unused by the IAP path (no login/callback).
    self.redirectUriField.stringValue = EnvDefault(@"REDIRECT_URI",
        @"com.open4id.example.ios://open4id/callback");
    // Universal-purchase identity: the same bundle id as the iOS app,
    // registered on both the `ios` and `macos` platform entries, and matching
    // the App Store `payments.app_store.bundle_id` used for JWS verification.
    self.bundleIdField.stringValue = EnvDefault(@"BUNDLE_ID",
        @"com.open4id.example.ios");
}

// MARK: - SDK calls (ObjC surface)

/// `configureWithAppId:environment:publicSdkKey:endpoint:redirectUri:scope:
/// bundleId:error:` — the `NSErrorPointer` overload; validation failures come
/// back as `NSError` with domain `Open4IDSDK`. Returns NO (and logs) on
/// failure.
- (BOOL)configureClient {
    NSError *error = nil;
    [self.appDelegate.client
              configureWithAppId:self.appIdField.stringValue
                      environment:self.environmentField.stringValue
                     publicSdkKey:self.publicSdkKeyField.stringValue
                         endpoint:self.endpointField.stringValue
                       redirectUri:self.redirectUriField.stringValue
                             scope:nil
                          bundleId:self.bundleIdField.stringValue
                             error:&error];
    if (error) {
        [self append:[NSString stringWithFormat:@"failed: %@", DescribeError(error)]];
        return NO;
    }
    if (!self.payments) {
        // The namespace objects are stable for the client's lifetime.
        self.payments = self.appDelegate.client.payments;
        self.entitlements = self.appDelegate.client.entitlements;
        // One call enables the whole payment feature: products from the SDK
        // catalog request, the StoreKit purchase pipeline, the restore proof
        // source (registered on the payments namespace automatically), and
        // the Transaction.updates listener.
        self.store = [self.appDelegate.client storeKitPayments];
        // Ask-to-buy approvals and cross-device buys complete outside the
        // Buy button's pipeline; the SDK verifies and finishes them
        // automatically and reports the outcome here (main queue).
        __weak typeof(self) weakSelf = self;
        self.store.onTransactionUpdate = ^(Open4IDPurchaseOutcome *outcome) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) { return; }
            if (outcome.isVerified) {
                [strongSelf append:[NSString stringWithFormat:
                    @"update %@: verified — granted (ask-to-buy approval or "
                    "cross-device buy); refresh entitlements",
                    outcome.productId]];
            } else {
                [strongSelf append:[NSString stringWithFormat:
                    @"update %@: %@", outcome.productId, outcome.kind]];
            }
        };
    }
    return YES;
}

/// Auto configure + bootstrap on launch, then the `OPEN4ID_AUTOTEST=payments`
/// rehearsal (shop load + purchase of the first resolvable row through the
/// SDK store; the StoreKit sheet still needs the human's confirm).
- (void)autoBootstrap {
    if (![self configureClient]) {
        [self append:@"bootstrap failed"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.appDelegate.client bootstrap:^(Bootstrap * _Nullable bootstrap,
                                         NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        OnMain(^{
        if (error) {
            [self append:[NSString stringWithFormat:@"bootstrap failed: %@",
                          DescribeError(error)]];
            return;
        }
        self.bootstrapValue.stringValue =
            bootstrap.displayName ?: bootstrap.appId;
        [self append:[NSString stringWithFormat:@"bootstrap ok: app=%@ payments=%d",
                      self.bootstrapValue.stringValue, bootstrap.payments.enabled]];
        NSString *autotest =
            [NSProcessInfo.processInfo.environment objectForKey:@"OPEN4ID_AUTOTEST"];
        if ([autotest isEqualToString:@"payments"]) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [self loadShopClicked:nil];
                    dispatch_after(dispatch_time(
                        DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                        // Buy the first resolvable row (the StoreKit sheet
                        // needs the human's confirm in DeviceHub).
                        for (Open4IDStoreProduct *row in self.shopRows) {
                            if (row.isResolvable) {
                                [self append:[NSString stringWithFormat:
                                    @"autotest: buying %@", row.product.productId]];
                                if (![self beginAction]) return;
                                [self buyRow:row];
                                return;
                            }
                        }
                    });
                });
        }
        });
    }];
}

// MARK: - Actions

/// Shared pre-flight for button actions: re-configure, then raise `busy`.
/// Returns NO (and logs) when a configure failed or an action is running.
/// Every action must clear `busy` on each of its terminal paths.
- (BOOL)beginAction {
    if (self.busy) return NO;
    if (![self configureClient]) return NO;
    self.busy = YES;
    [self syncBusyUI];
    return YES;
}

- (void)endAction {
    self.busy = NO;
    [self syncBusyUI];
}

- (void)syncBusyUI {
    for (NSButton *button in self.actionButtons) {
        button.enabled = !self.busy;
    }
    for (NSView *view in self.buyButtonsStack.arrangedSubviews) {
        if ([view isKindOfClass:[NSButton class]]) {
            ((NSButton *)view).enabled = !self.busy;
        }
    }
}

- (void)loadBootstrapClicked:(NSButton *)sender {
    if (![self beginAction]) return;
    __weak typeof(self) weakSelf = self;
    [self.appDelegate.client bootstrap:^(Bootstrap * _Nullable bootstrap,
                                         NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        OnMain(^{
        [self endAction];
        if (error) {
            [self append:[NSString stringWithFormat:@"failed: %@",
                          DescribeError(error)]];
            return;
        }
        self.bootstrapValue.stringValue =
            bootstrap.displayName ?: bootstrap.appId;
        [self append:[NSString stringWithFormat:@"bootstrap ok: app=%@ payments=%d",
                      self.bootstrapValue.stringValue, bootstrap.payments.enabled]];
        });
    }];
}

/// Loads the shop: the catalog log comes from the SDK request (both stores),
/// and the Buy-button rows come from the SDK's built-in store
/// (`loadProducts:` — catalog rows joined with StoreKit products and prices;
/// the scheme's StoreKit test configuration locally, the App Store sandbox
/// on a device). The shop UI stays this sample's job — one Buy button per
/// row, exactly like a game renders its own.
- (void)loadShopClicked:(NSButton * _Nullable)sender {
    if (![self beginAction]) return;
    __weak typeof(self) weakSelf = self;
    PaymentCatalog *catalog = [self.payments products];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    if (catalog.enabled) {
        for (PaymentProduct *product in catalog.products) {
            [rows addObject:[NSString stringWithFormat:@"%@[%@/%@]",
                product.productId, product.platform, product.type]];
        }
        [rows sortUsingSelector:@selector(compare:)];
    }
    [self append:[NSString stringWithFormat:
        @"payments catalog: enabled=%d rows=[%@]",
        catalog.enabled, [rows componentsJoinedByString:@" "]]];
    [self.store loadProducts:^(NSArray<Open4IDStoreProduct *> * _Nullable products,
                               NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        OnMain(^{
        [self endAction];
        if (error) {
            [self append:[NSString stringWithFormat:@"failed: %@",
                          DescribeError(error)]];
            return;
        }
        self.shopRows = products;
        [self rebuildBuyButtons];
        NSMutableArray<NSString *> *described = [NSMutableArray array];
        for (Open4IDStoreProduct *row in products) {
            [described addObject:[NSString stringWithFormat:@"%@ %@",
                row.product.productId, row.displayPrice ?: @"-"]];
        }
        [self append:[NSString stringWithFormat:@"storekit: %lu products %@",
            (unsigned long)products.count,
            [described componentsJoinedByString:@", "]]];
        });
    }];
}

/// One Buy button: the SDK's built-in store runs the whole pipeline
/// (StoreKit sheet → JWS proof → verify → finish); this sample only renders
/// the outcome, like a game would.
- (void)buyRowClicked:(NSButton *)sender {
    Open4IDStoreProduct *row = self.rowsByTag[@(sender.tag)];
    if (!row || self.busy) return;
    if (![self beginAction]) return;
    [self buyRow:row];
}

- (void)buyRow:(Open4IDStoreProduct *)row {
    // The row in hand is exactly what the user clicked — pass it as-is so
    // the pipeline never re-looks it up against a possibly stale snapshot.
    __weak typeof(self) weakSelf = self;
    [self.store purchase:row.product
              completion:^(Open4IDPurchaseOutcome * _Nullable outcome,
                           NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        OnMain(^{
        [self endAction];
        if (error) {
            [self append:[NSString stringWithFormat:@"buy %@: failed → %@",
                          row.product.productId, DescribeError(error)]];
            return;
        }
        if (outcome.isVerified) {
            if (outcome.receipt) {
                [self append:[NSString stringWithFormat:
                    @"buy %@: verifyConsumable ok state=%@ quantity=%ld ref=%@",
                    row.product.productId, outcome.receipt.state,
                    (long)outcome.receipt.quantity, outcome.receipt.transactionRef]];
            } else {
                NSMutableArray<NSString *> *keys = [NSMutableArray array];
                BOOL expiredGrant = NO;
                for (Entitlement *entitlement in outcome.entitlements) {
                    [keys addObject:[NSString stringWithFormat:@"%@ [%@, expires=%@]",
                        entitlement.key, entitlement.state,
                        entitlement.expiresAt ?: @"-"]];
                    if ([entitlement.state isEqualToString:@"expired"]) {
                        expiredGrant = YES;
                    }
                }
                [keys sortUsingSelector:@selector(compare:)];
                [self append:[NSString stringWithFormat:
                    @"buy %@: verifyTransaction ok, %lu entitlement(s) %@",
                    row.product.productId, (unsigned long)outcome.entitlements.count,
                    [keys componentsJoinedByString:@", "]]];
                if (expiredGrant) {
                    // Re-purchase of a lapsed subscription: Apple's sandbox
                    // returns the existing transaction WITHOUT a sheet, so
                    // no payment happens. Production resubscribes normally;
                    // see the README's subscription section for the local
                    // StoreKit path that re-purchases with a fresh sheet.
                    [self append:@"storekit: no sheet shown — Apple's sandbox "
                        "returned the subscription's existing (lapsed) "
                        "transaction instead of the purchase sheet, so no new "
                        "payment started. Known sandbox limitation. In "
                        "production the resubscribe sheet shows and starts a "
                        "new cycle. To re-test here: clear the sandbox "
                        "tester's subscription history (App Store Connect → "
                        "Users and Access → Sandbox → the tester), or run via "
                        "Xcode so the local StoreKit configuration applies — "
                        "expired subscriptions re-purchase with a fresh "
                        "sheet there."];
                }
            }
        } else if (outcome.isPending) {
            [self append:[NSString stringWithFormat:
                @"buy %@: pending (ask-to-buy)", row.product.productId]];
        } else {
            [self append:[NSString stringWithFormat:
                @"buy %@: cancelled by user", row.product.productId]];
            if ([row.product.type isEqualToString:@"subscription"]) {
                // Apple refuses a second purchase of a subscription the
                // store account still holds ("You're currently subscribed
                // to this") and surfaces it as userCancelled — no payment
                // happens. The subscription becomes re-purchasable after
                // it lapses.
                [self append:@"storekit: Apple refused the second purchase — "
                    "the store account still holds an active subscription "
                    "for this product. It becomes re-purchasable once it "
                    "lapses (sandbox 1-month ≈ 5 minutes)."];
            }
        }
        });
    }];
}

/// SDK restore through the proof source the built-in store registered
/// (`Transaction.currentEntitlements`).
- (void)restoreClicked:(NSButton *)sender {
    if (![self beginAction]) return;
    __weak typeof(self) weakSelf = self;
    [self.payments restore:^(RestoreResult * _Nullable result,
                             NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        OnMain(^{
        [self endAction];
        if (error) {
            [self append:[NSString stringWithFormat:@"failed: %@",
                          DescribeError(error)]];
            return;
        }
        [self append:[NSString stringWithFormat:
            @"restore ok: verified=%ld rejected=%ld conflict=%ld noProofs=%d",
            (long)result.verified, (long)result.rejected, (long)result.conflict,
            result.proofsUnavailable]];
        });
    }];
}

- (void)entitlementsClicked:(NSButton *)sender {
    if (![self beginAction]) return;
    __weak typeof(self) weakSelf = self;
    [self.entitlements refresh:^(EntitlementSnapshot * _Nullable snapshot,
                                 NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        OnMain(^{
        [self endAction];
        if (error) {
            [self append:[NSString stringWithFormat:@"failed: %@",
                          DescribeError(error)]];
            return;
        }
        NSMutableArray<NSString *> *list = [NSMutableArray array];
        for (Entitlement *entitlement in snapshot.entitlements) {
            [list addObject:[NSString stringWithFormat:
                @"%@ [state=%@, src=%@, product=%@, expires=%@]",
                entitlement.key, entitlement.state, entitlement.source,
                entitlement.productId ?: @"-", entitlement.expiresAt ?: @"-"]];
        }
        [list sortUsingSelector:@selector(compare:)];
        [self append:[NSString stringWithFormat:@"entitlements: %lu -> [%@]",
            (unsigned long)snapshot.entitlements.count,
            [list componentsJoinedByString:@" "]]];
        });
    }];
}

// MARK: - UI construction

- (void)buildUI {
    // Configuration fields.
    NSTextField *appIdField = nil;
    NSTextField *environmentField = nil;
    NSTextField *publicSdkKeyField = nil;
    NSTextField *endpointField = nil;
    NSTextField *bundleIdField = nil;
    NSTextField *redirectUriField = nil;
    NSView *configSection = [self
        sectionWithTitle:@"Configuration" views:@[
            [self fieldRowWithTitle:@"App ID" outField:&appIdField],
            [self fieldRowWithTitle:@"Environment" outField:&environmentField],
            [self fieldRowWithTitle:@"Public SDK key" outField:&publicSdkKeyField],
            [self fieldRowWithTitle:@"Endpoint" outField:&endpointField],
            [self fieldRowWithTitle:@"Bundle ID" outField:&bundleIdField],
            [self fieldRowWithTitle:@"Redirect URI" outField:&redirectUriField],
        ]];
    self.appIdField = appIdField;
    self.environmentField = environmentField;
    self.publicSdkKeyField = publicSdkKeyField;
    self.endpointField = endpointField;
    self.bundleIdField = bundleIdField;
    self.redirectUriField = redirectUriField;

    // Bootstrap section.
    self.bootstrapValue = [NSTextField labelWithString:@"-"];
    NSButton *bootstrapButton = [self
        actionButtonWithTitle:@"Load bootstrap"
                       action:@selector(loadBootstrapClicked:)];
    NSView *bootstrapSection = [self sectionWithTitle:@"Bootstrap" views:@[
        [self rowWithViews:@[[NSTextField labelWithString:@"Application"],
                            self.bootstrapValue]],
        bootstrapButton,
    ]];

    // Payments section: the SDK's built-in store feeds the Buy buttons; the
    // shop UI itself is host-owned (this sample's AppKit stack).
    self.buyButtonsStack = [[NSStackView alloc] init];
    self.buyButtonsStack.orientation =
        NSUserInterfaceLayoutOrientationVertical;
    self.buyButtonsStack.alignment = NSLayoutAttributeLeading;
    self.buyButtonsStack.spacing = 4;
    [self.buyButtonsStack addArrangedSubview:
        [NSTextField labelWithString:
            @"(no shop rows — load the shop first)"]];
    NSView *paymentsSection = [self sectionWithTitle:@"Payments (App Store)"
                                               views:@[
        [self actionButtonWithTitle:@"Load shop (SDK store)"
                             action:@selector(loadShopClicked:)],
        self.buyButtonsStack,
        [self actionButtonWithTitle:@"Restore purchases"
                             action:@selector(restoreClicked:)],
        [self actionButtonWithTitle:@"Entitlements (ledger)"
                             action:@selector(entitlementsClicked:)],
    ]];

    // Log console.
    self.logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 640, 220)];
    self.logView.editable = NO;
    self.logView.richText = NO;
    self.logView.font = [NSFont monospacedSystemFontOfSize:11
                                                    weight:NSFontWeightRegular];
    self.logView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    // Wrap at the visible width: a horizontally resizable text view as a
    // scroll view's document view grows with its content and, inside a
    // leading-aligned stack, collapses the text column to nothing.
    self.logView.horizontallyResizable = NO;
    self.logView.verticallyResizable = YES;
    self.logView.textContainer.widthTracksTextView = YES;
    self.logView.minSize = NSMakeSize(0.0, 220.0);
    self.logView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    NSScrollView *logScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    logScroll.hasVerticalScroller = YES;
    logScroll.documentView = self.logView;
    logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [logScroll.heightAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
    NSView *logSection = [self sectionWithTitle:@"Log" views:@[logScroll]];

    // Root layout inside a scroll view (the SwiftUI sibling uses a Form).
    NSStackView *root = [NSStackView stackViewWithViews:@[
        configSection, bootstrapSection, paymentsSection, logSection]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 16;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    // The log scroll view must fill the stack's width: a leading-aligned
    // stack sizes arranged views to their intrinsic width, and a scroll
    // view has none — its text column collapsed to a single character
    // (the edge insets are 16pt each side).
    [logScroll.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                         multiplier:1.0
                                           constant:-32.0].active = YES;

    NSScrollView *outer = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    outer.hasVerticalScroller = YES;
    outer.documentView = root;
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:outer];
    // Top, leading, and trailing only: the content height comes from the
    // stack's intrinsic size, so the outer scroll view can scroll it.
    [NSLayoutConstraint activateConstraints:@[
        [outer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [outer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [outer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [outer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [root.topAnchor constraintEqualToAnchor:outer.contentView.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:outer.contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:outer.contentView.trailingAnchor],
    ]];
}

- (NSButton *)actionButtonWithTitle:(NSString *)title
                             action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title
                                          target:self
                                          action:action];
    [self.actionButtons addObject:button];
    return button;
}

- (NSView *)sectionWithTitle:(NSString *)title
                       views:(NSArray<NSView *> *)views {
    NSTextField *header = [NSTextField labelWithString:title];
    header.font = [NSFont boldSystemFontOfSize:12];
    NSStackView *stack =
        [NSStackView stackViewWithViews:[@[header]
            arrayByAddingObjectsFromArray:views]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    return stack;
}

- (NSView *)rowWithViews:(NSArray<NSView *> *)views {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeFirstBaseline;
    row.spacing = 8;
    return row;
}

- (NSView *)fieldRowWithTitle:(NSString *)title
                     outField:(NSTextField **)outField {
    NSTextField *label = [NSTextField labelWithString:title];
    [label.widthAnchor constraintEqualToConstant:110].active = YES;
    NSTextField *field = [NSTextField textFieldWithString:@""];
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:380].active = YES;
    NSView *row = [self rowWithViews:@[label, field]];
    if (outField) *outField = field;
    return row;
}

/// One Buy button per shop row. Rows the store could not resolve
/// (`isResolvable == NO`) render disabled instead of disappearing, so a
/// missing product is visible, not silent.
- (void)rebuildBuyButtons {
    for (NSView *view in self.buyButtonsStack.arrangedSubviews) {
        [view removeFromSuperview];
    }
    [self.rowsByTag removeAllObjects];
    if (self.shopRows.count == 0) {
        [self.buyButtonsStack addArrangedSubview:
            [NSTextField labelWithString:
                @"(no shop rows — load the shop first)"]];
        return;
    }
    NSInteger tag = 0;
    for (Open4IDStoreProduct *row in self.shopRows) {
        NSString *price = row.displayPrice;
        NSString *suffix = price.length ? [NSString stringWithFormat:@" %@", price]
                                        : @"";
        NSButton *button = [NSButton
            buttonWithTitle:[NSString stringWithFormat:@"Buy %@ [%@]%@",
                             row.product.productId, row.product.type, suffix]
                     target:self
                     action:@selector(buyRowClicked:)];
        button.tag = tag++;
        button.enabled = row.isResolvable && !self.busy;
        [self.buyButtonsStack addArrangedSubview:button];
        self.rowsByTag[@(button.tag)] = row;
    }
}

// MARK: - Log console

- (void)append:(NSString *)line {
    [self.logLines addObject:line];
    [self.logView.textStorage appendAttributedString:
        [[NSAttributedString alloc]
            initWithString:[line stringByAppendingString:@"\n"]
                attributes:nil]];
    [self.logView scrollRangeToVisible:
        NSMakeRange(self.logView.string.length, 0)];
    NSLog(@"[open4id-iap] %@", line);
    const char *utf8 = line.UTF8String;
    os_log_info(self.console, "open4id-iap: %{public}s",
                utf8 ? utf8 : "");
    [self persistLog];
}

/// Mirrors the log console into Documents/open4id-log-objc.txt so a session
/// can be inspected afterwards (the Swift sibling writes
/// `open4id-log.txt`; the suffix keeps both from clobbering each other).
- (void)persistLog {
    NSArray<NSURL *> *documents =
        [[NSFileManager defaultManager]
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = documents.firstObject;
    if (!url) return;
    NSString *text = [self.logLines componentsJoinedByString:@"\n"];
    [text writeToURL:[url URLByAppendingPathComponent:@"open4id-log-objc.txt"]
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:NULL];
}

@end

NS_ASSUME_NONNULL_END
