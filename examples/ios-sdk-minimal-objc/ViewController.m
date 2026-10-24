#import "ViewController.h"
#import "AppDelegate.h"
#import "Open4IDSocialClient.h"
@import Open4IDSDK;

NS_ASSUME_NONNULL_BEGIN

/// Mirrors `examples/ios-sdk-minimal/ContentView.swift`: editable
/// configuration fields, the same action order (bootstrap, social row,
/// refresh, credentials, user, sign-out, delete), and an append-only log
/// console. Pure Objective-C — no SwiftUI.
@interface ViewController ()

@property (strong, nonatomic) UIScrollView *scrollView;
@property (strong, nonatomic) UIView *formView;

/// Configuration fields
@property (strong, nonatomic) UITextField *appIdField;
@property (strong, nonatomic) UITextField *environmentField;
@property (strong, nonatomic) UITextField *publicSdkKeyField;
@property (strong, nonatomic) UITextField *endpointField;
@property (strong, nonatomic) UITextField *portalOriginField;
@property (strong, nonatomic) UITextField *redirectUriField;
@property (strong, nonatomic) UITextField *bundleIdField;
@property (strong, nonatomic) UITextField *googleIosClientIdField;

/// Credentials fields
@property (strong, nonatomic) UITextField *emailField;
@property (strong, nonatomic) UITextField *passwordField;
@property (strong, nonatomic) UITextField *emailField2; // for register/reset

/// Session + log
@property (strong, nonatomic) UILabel *sessionLabel;
@property (strong, nonatomic) UITextView *logView;
@property (strong, nonatomic) NSMutableArray<NSString *> *logLines;
@property (nonatomic, assign) BOOL busy;

/// Last fetched bootstrap (drives the login dialog's provider list).
@property (strong, nonatomic) Bootstrap *lastBootstrap;
/// Handle of the currently presented login dialog (close on demand).
@property (strong, nonatomic) Open4IDLoginDialogHandleObjC *loginDialogHandle;

/// Vertical stack holding every section (Auto Layout driven).
@property (strong, nonatomic) UIStackView *stackView;

/// Auth-state listener token (unsubscribe closure)
@property (strong, nonatomic) void (^ _Nullable authListenerUnsubscribe)(void);

@end

@implementation ViewController

static NSString *const kDefaultAppId = @"app_4a17c6406abaefdf0d9a705e7175b37c";
static NSString *const kDefaultEnvironment = @"development";
static NSString *const kDefaultPublicSdkKey =
    @"sdk_pk_24cf6cc954d16591812fd1b9953ef053f5133b13f7cec9ae";
/// Dev fixture / launch-override defaults: `SIMCTL_CHILD_OPEN4ID_*`
/// environment variables pre-fill the config fields (same hook as the
/// Swift sibling sample) and `OPEN4ID_AUTOTEST` auto-runs one web flow.
static NSString *const kEnvEndpoint = @"OPEN4ID_ENDPOINT";
static NSString *const kEnvPortalOrigin = @"OPEN4ID_PORTAL_ORIGIN";
static NSString *const kEnvAutotest = @"OPEN4ID_AUTOTEST";

/// Launch-time field default (environment override pre-fills; empty keeps
/// the built-in fixture default).
static NSString *const kDefaultEndpoint = @"https://id.open4id.com/api";
static NSString *const kDefaultPortalOrigin = @"https://app.open4id.com";
static NSString *const kDefaultRedirectUri =
    @"com.open4id.example.ios://open4id/callback";
static NSString *const kDefaultBundleId = @"com.open4id.example.ios";
static NSString *const kDefaultGoogleIosClientId =
    @"240704269959-fgo38gpqj16f9ompn9kb1mcej1e4fo84.apps.googleusercontent.com";

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.logLines = [NSMutableArray arrayWithObject:@"[open4id-minimal-objc] Ready."];

    [self buildUI];
    [self reloadLog];
    // The shared client (Google-sign-in subclass).
    Open4IDAuthClient *client = [(AppDelegate *)[[UIApplication sharedApplication] delegate] authClient];

    // Register the auth-state listener so sign-in/sign-out events update
    // the UI — this is the ObjC side of the SDK's login-state-changed event.
    self.authListenerUnsubscribe = [client onAuthStateChanged:^(AuthSession * _Nullable session,
                                                                 UserInfo * _Nullable user) {
        if (session) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.sessionLabel.text = [NSString stringWithFormat:@"sub=%@ scope=%@",
                                          session.userId, session.scope];
                [self appendLog:[NSString stringWithFormat:@"signed in: sub=%@", session.userId]];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.sessionLabel.text = @"not signed in";
                [self appendLog:@"signed out"];
            });
        }
    }];

    // Auto configure + bootstrap on launch (same behavior as the Swift
    // sibling sample) so a device/simulator launch proves the live path.
    [self performAutoLaunch];
}

- (void)dealloc {
    if (self.authListenerUnsubscribe) {
        self.authListenerUnsubscribe();
    }
}

#pragma mark - UI building

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth
        | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.formView = [[UIView alloc] init];
    self.formView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.formView];

    // Scroll view pinned to the safe area of the root view; the form view
    // matches the scroll view's width.
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.formView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.formView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.formView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.formView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.formView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
    ]];

    [self buildStack];

    CGFloat fieldHeight = 30.0f;
    CGFloat buttonHeight = 38.0f;

    // MARK: Configuration section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Configuration"]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"App ID" field:[self textFieldWithPlaceholder:@"App ID" defaultValue:kDefaultAppId] height:fieldHeight storingTo:&_appIdField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Environment" field:[self textFieldWithPlaceholder:@"Environment" defaultValue:kDefaultEnvironment] height:fieldHeight storingTo:&_environmentField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Public SDK key" field:[self textFieldWithPlaceholder:@"Public SDK key" defaultValue:kDefaultPublicSdkKey] height:fieldHeight storingTo:&_publicSdkKeyField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Endpoint" field:[self textFieldWithPlaceholder:@"Endpoint" defaultValue:[self fieldDefault:kDefaultEndpoint envKey:kEnvEndpoint]] height:fieldHeight storingTo:&_endpointField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Portal origin" field:[self textFieldWithPlaceholder:@"Portal origin" defaultValue:[self fieldDefault:kDefaultPortalOrigin envKey:kEnvPortalOrigin]] height:fieldHeight storingTo:&_portalOriginField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Redirect URI" field:[self textFieldWithPlaceholder:@"Redirect URI" defaultValue:kDefaultRedirectUri] height:fieldHeight storingTo:&_redirectUriField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Bundle ID" field:[self textFieldWithPlaceholder:@"Bundle ID" defaultValue:kDefaultBundleId] height:fieldHeight storingTo:&_bundleIdField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Google iOS client ID" field:[self textFieldWithPlaceholder:@"Google iOS client ID" defaultValue:kDefaultGoogleIosClientId] height:fieldHeight storingTo:&_googleIosClientIdField]];

    // MARK: Bootstrap section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Bootstrap"]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Load bootstrap" action:@selector(tapLoadBootstrap) height:buttonHeight style:UIButtonTypeSystem]];

    // MARK: Social section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Social"]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Sign in with Google" action:@selector(tapSignInGoogle) height:buttonHeight style:UIButtonTypeSystem]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Continue as guest" action:@selector(tapContinueAsGuest) height:buttonHeight style:UIButtonTypeSystem]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Sign in with GitHub" action:@selector(tapSignInGitHub) height:buttonHeight style:UIButtonTypeSystem]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Sign in with Facebook" action:@selector(tapSignInFacebook) height:buttonHeight style:UIButtonTypeSystem]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Sign in with Apple" action:@selector(tapSignInApple) height:buttonHeight style:UIButtonTypeSystem]];

    // MARK: Session section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Session"]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Refresh session" action:@selector(tapRefreshSession) height:buttonHeight style:UIButtonTypeSystem]];

    self.sessionLabel = [[UILabel alloc] init];
    self.sessionLabel.text = @"not signed in";
    self.sessionLabel.font = [UIFont systemFontOfSize:14];
    self.sessionLabel.textColor = [UIColor secondaryLabelColor];
    [self.stackView addArrangedSubview:self.sessionLabel];

    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Sign out" action:@selector(tapSignOut) height:buttonHeight style:UIButtonTypeSystem]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Delete account" action:@selector(tapDeleteAccount) height:buttonHeight style:UIButtonTypeSystem]];

    // MARK: Email / password section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Email / password"]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Email" field:[self textFieldWithPlaceholder:@"Email" defaultValue:@""] height:fieldHeight storingTo:&_emailField]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Password" field:[self textFieldWithPlaceholder:@"Password" defaultValue:@""] height:fieldHeight secure:YES storingTo:&_passwordField]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Sign in" action:@selector(tapSignInPassword) height:buttonHeight style:UIButtonTypeSystem]];
    [self.stackView addArrangedSubview:
        [self labeledField:@"Email" field:[self textFieldWithPlaceholder:@"Email" defaultValue:@""] height:fieldHeight storingTo:&_emailField2]];

    [self.stackView addArrangedSubview:[self rowWithButtons:@[
        [self buttonWithTitle:@"Register" action:@selector(tapRegister) height:buttonHeight style:UIButtonTypeSystem],
        [self buttonWithTitle:@"Forgot password" action:@selector(tapRequestReset) height:buttonHeight style:UIButtonTypeSystem],
    ]]];

    // MARK: Account section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Account"]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Get user" action:@selector(tapGetUser) height:buttonHeight style:UIButtonTypeSystem]];

    // MARK: Login UI section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Login UI"]];
    [self.stackView addArrangedSubview:[self buttonWithTitle:@"Open login dialog" action:@selector(tapOpenLoginDialog) height:buttonHeight style:UIButtonTypeSystem]];

    // MARK: Log section
    [self.stackView addArrangedSubview:[self sectionLabel:@"Log"]];

    self.logView = [[UITextView alloc] init];
    self.logView.font = [UIFont systemFontOfSize:11];
    self.logView.textColor = [UIColor labelColor];
    self.logView.backgroundColor = [UIColor systemGray6Color];
    self.logView.layer.cornerRadius = 6.0f;
    self.logView.editable = NO;
    [self.logView.heightAnchor constraintEqualToConstant:150.0f].active = YES;
    [self.stackView addArrangedSubview:self.logView];
}

/// Creates the vertical stack that contains every section. Called before
/// sections are appended, so sections can just add arranged subviews.
- (void)buildStack {
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 8.0f;
    self.stackView.alignment = UIStackViewAlignmentFill;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.formView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.formView.leadingAnchor constant:12.0f],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.formView.trailingAnchor constant:-12.0f],
        [self.stackView.topAnchor constraintEqualToAnchor:self.formView.topAnchor constant:12.0f],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.formView.bottomAnchor constant:-12.0f],
    ]];
}

/// Wraps two buttons side by side in a horizontal stack (Register /
/// Forgot password). Splitting is equal-width with an 8pt gap.
- (UIStackView *)rowWithButtons:(NSArray<UIButton *> *)buttons {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8.0f;
    row.distribution = UIStackViewDistributionFillEqually;
    for (UIButton *button in buttons) {
        [row addArrangedSubview:button];
    }
    return row;
}

/// A section heading (bold gray label). Adds 20pt of extra space before the
/// heading (instead of the stack's default 8pt) so sections group visually.
- (UILabel *)sectionLabel:(NSString *)title {
    UIView *last = self.stackView.arrangedSubviews.lastObject;
    if (last) {
        [self.stackView setCustomSpacing:20.0f afterView:last];
    }
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:15];
    label.textColor = [UIColor secondaryLabelColor];
    return label;
}

/// A label + text-field row. The field stretches to fill the remaining
/// width. Stores the field via IBOutlet-style indirection so callers can
/// keep a reference (the ObjC pattern `storingTo:&_prop`).
- (UIView *)labeledField:(NSString *)labelText field:(UITextField *)field height:(CGFloat)height storingTo:(UITextField *__strong * _Nullable)storingTo {
    return [self labeledField:labelText field:field height:height secure:NO storingTo:storingTo];
}

- (UIView *)labeledField:(NSString *)labelText field:(UITextField *)field height:(CGFloat)height secure:(BOOL)secure storingTo:(UITextField *__strong * _Nullable)storingTo {
    field.secureTextEntry = secure;

    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8.0f;
    row.alignment = UIStackViewAlignmentCenter;

    UILabel *label = [[UILabel alloc] init];
    label.text = labelText;
    label.font = [UIFont systemFontOfSize:14];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired
                                          forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityRequired
                             forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:label];
    [row addArrangedSubview:field];

    // The field is the flexible element of the row: minimal hugging so it
    // absorbs all remaining width after the label.
    [field setContentHuggingPriority:1.0f
                             forAxis:UILayoutConstraintAxisHorizontal];

    [field.heightAnchor constraintEqualToConstant:height].active = YES;
    [label.widthAnchor constraintGreaterThanOrEqualToConstant:110.0f].active = YES;

    if (storingTo) {
        *storingTo = field;
    }
    return row;
}

- (NSString *)fieldDefault:(NSString *)fallback envKey:(NSString *)key {
    NSString *value = [NSProcessInfo.processInfo.environment objectForKey:key];
    return value.length ? value : fallback;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder defaultValue:(NSString *)defaultValue {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.text = defaultValue;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont systemFontOfSize:14];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    return field;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action height:(CGFloat)height style:(UIButtonType)style {
    UIButton *button = [UIButton buttonWithType:style];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont systemFontOfSize:14];
    if (style == UIButtonTypeSystem) {
        button.backgroundColor = [UIColor systemBlueColor];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [UIColor systemRedColor];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    [button.heightAnchor constraintEqualToConstant:height].active = YES;
    return button;
}

#pragma mark - Helpers

- (Open4IDAuthClient *)authClient {
    return [(AppDelegate *)[[UIApplication sharedApplication] delegate] authClient];
}

- (Open4IDSocialClient *)socialClient {
    return [(AppDelegate *)[[UIApplication sharedApplication] delegate] socialClient];
}

- (void)configureClientWithError:(NSError * _Nullable * _Nullable)error {
    Open4IDAuthClient *client = self.authClient;
    [self.socialClient setGoogleIosClientId:self.googleIosClientIdField.text];
    [client configureWithAppId:self.appIdField.text
                     environment:self.environmentField.text
                 publicSdkKey:self.publicSdkKeyField.text
                        endpoint:self.endpointField.text
                    redirectUri:self.redirectUriField.text
                           scope:nil
                       bundleId:self.bundleIdField.text
                          error:error];
    if (error && *error) return;
    // The per-app Portal bridges (github/facebook/apple-callback) resolve
    // against this origin — never resets session state, so it is safe on
    // every configure (validation errors surface through `error` too).
    [client setPortalOriginWithPortalOrigin:self.portalOriginField.text error:error];
}

- (void)runAction:(void (^ _Nullable)(NSError * _Nullable))action {
    if (self.busy) return;
    self.busy = YES;

    NSError *configureError = nil;
    [self configureClientWithError:&configureError];
    if (configureError) {
        self.busy = NO;
        [self appendLog:[NSString stringWithFormat:@"configure failed: %@", configureError.userInfo[@"key"] ?: configureError.localizedDescription]];
        return;
    }

    action(configureError);
    self.busy = NO;
}

- (void)appendLog:(NSString *)line {
    [self.logLines addObject:line];
    NSLog(@"[open4id-minimal-objc] %@", line);
    [self reloadLog];
}

- (void)reloadLog {
    NSString *combined = [self.logLines componentsJoinedByString:@"\n"];
    self.logView.text = combined;
    // Scroll to bottom.
    NSRange bottomRange = NSMakeRange(combined.length > 0 ? combined.length - 1 : 0, 1);
    [self.logView scrollRangeToVisible:bottomRange];
}

#pragma mark - Auto launch

- (void)performAutoLaunch {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;

        Open4IDAuthClient *client = self.authClient;
        [client bootstrap:^(Bootstrap * _Nullable bootstrap, NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"bootstrap failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"bootstrap ok: app=%@ google=%@",
                                 bootstrap.displayName ?: bootstrap.appId,
                                 bootstrap.login.google.enabled ? @"true" : @"false"]];
                self.lastBootstrap = bootstrap;
                [self runAutotestIfRequested];
            });
        }];
    }];
}

/// Debug hook for automated verification (mirrors the Swift sibling
/// sample): when launched with `OPEN4ID_AUTOTEST=facebook`, auto-run one
/// web flow after a 5 s settle delay so the typed outcome lands in the
/// log console without tapping anything.
- (void)runAutotestIfRequested {
    NSString *autotest = [NSProcessInfo.processInfo.environment objectForKey:kEnvAutotest];
    if (!autotest.length) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([autotest isEqualToString:@"facebook"]) {
            [self tapSignInFacebook];
        } else if ([autotest isEqualToString:@"github"]) {
            [self tapSignInGitHub];
        } else if ([autotest isEqualToString:@"apple"]) {
            [self tapSignInApple];
        }
    });
}

#pragma mark - Actions

- (void)tapLoadBootstrap {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient bootstrap:^(Bootstrap * _Nullable bootstrap, NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"bootstrap failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"bootstrap ok: app=%@ google=%@",
                                 bootstrap.displayName ?: bootstrap.appId,
                                 bootstrap.login.google.enabled ? @"true" : @"false"]];
                self.lastBootstrap = bootstrap;
            });
        }];
    }];
}

- (void)tapSignInGoogle {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient signInWithGoogle:^(AuthSession * _Nullable session, NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"google failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"google ok: sub=%@ scope=%@",
                                 session.userId, session.scope]];
            });
        }];
    }];
}

- (void)tapContinueAsGuest {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient continueAsGuest:^(AuthSession * _Nullable session, NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"guest failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"guest ok: sub=%@ scope=%@",
                                 session.userId, session.scope]];
            });
        }];
    }];
}

- (void)tapSignInGitHub {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient signInWithGitHubWithCallbackUri:nil
                                               completion:^(AuthSession * _Nullable session,
                                                            NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"github failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"github ok: sub=%@ scope=%@",
                                 session.userId, session.scope]];
            });
        }];
    }];
}

- (void)tapSignInFacebook {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient signInWithFacebookWithCallbackUri:nil
                                                completion:^(AuthSession * _Nullable session,
                                                             NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"facebook failed: %@",
                                      err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"facebook ok: sub=%@ scope=%@",
                                  session.userId, session.scope]];
            });
        }];
    }];
}

- (void)tapSignInApple {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient signInWithAppleWithReturnUri:nil
                                            completion:^(AuthSession * _Nullable session,
                                                         NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"apple failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"apple ok: sub=%@ scope=%@",
                                 session.userId, session.scope]];
            });
        }];
    }];
}

- (void)tapRefreshSession {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient refresh:^(AuthSession * _Nullable session, NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"refresh failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"refresh ok: sub=%@", session.userId]];
            });
        }];
    }];
}

- (void)tapSignInPassword {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient signInWithPasswordWithEmail:self.emailField.text
                                              password:self.passwordField.text
                                        completion:^(AuthSession * _Nullable session,
                                                     NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"sign-in failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"sign-in ok: sub=%@ scope=%@",
                                 session.userId, session.scope]];
            });
        }];
    }];
}

- (void)tapRegister {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient registerWithEmail:self.emailField2.text
                                  password:self.passwordField.text
                                completion:^(NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"register failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:@"register ok: verification email sent (generic response)"];
            });
        }];
    }];
}

- (void)tapRequestReset {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient requestPasswordResetWithEmail:self.emailField2.text
                                              completion:^(NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"reset failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:@"reset email requested (generic response)"];
            });
        }];
    }];
}

#pragma mark - Login UI (SDK phase 13)

/// Mirrors the Swift sibling's `prepareLoginUI()` + present: the ObjC
/// facade binds a fresh `Open4IDAuthViewModel` to the live client and the
/// last bootstrap before the dialog opens (Android `setAuthClient` +
/// `setBootstrap`), then presents the same centered-card dialog. The
/// client was configured + bootstrapped by the auto-launch, so provider
/// availability matches the headless buttons above.
- (void)tapOpenLoginDialog {
    [self appendLog:@"login ui: opening dialog"];
    self.loginDialogHandle = [Open4IDLoginDialogObjC
        showOn:self
        client:self.authClient
        bootstrap:self.lastBootstrap
        localeTag:@"en"
        dismissOnSignIn:YES
        onSignedIn:^(NSString *provider) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:
                    [NSString stringWithFormat:@"login ui: signed in provider=%@", provider]];
            });
        }
        onSignedOut:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:@"login ui: signed out"];
            });
        }
        onAccountDeleted:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:@"login ui: account deleted"];
            });
        }];
}

- (void)tapGetUser {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient getUser:^(UserInfo * _Nullable user, NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"get-user failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"user: sub=%@%@ verified=%@",
                                 user.sub,
                                 user.email ? [NSString stringWithFormat:@" email=%@", user.email] : @"",
                                 user.emailVerified ? @"true" : @"false"]];
            });
        }];
    }];
}

- (void)tapSignOut {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient signOut:^(NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"sign-out failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:@"signed out"];
            });
        }];
    }];
}

- (void)tapDeleteAccount {
    [self runAction:^(NSError * _Nullable error) {
        if (error) return;
        [self.authClient deleteAccount:^(NSError * _Nullable err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendLog:[NSString stringWithFormat:@"delete failed: %@",
                                     err.userInfo[@"key"] ?: err.localizedDescription]];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:@"account deleted"];
            });
        }];
    }];
}

@end

NS_ASSUME_NONNULL_END
