#import "EditSaveViewController.h"
#import "WikiTextSectionUploader.h"
#import <WMF/SessionSingleton.h>
#import "PaddedLabel.h"
#import "MenuButton.h"
#import "PreviewLicenseView.h"
#import "AbuseFilterAlert.h"
#import "SavedPagesFunnel.h"
#import "EditFunnel.h"
#import "Wikipedia-Swift.h"

typedef NS_ENUM(NSInteger, WMFCannedSummaryChoices) {
    CANNED_SUMMARY_TYPOS,
    CANNED_SUMMARY_GRAMMAR,
    CANNED_SUMMARY_LINKS,
    CANNED_SUMMARY_OTHER
};

typedef NS_ENUM(NSInteger, WMFPreviewAndSaveMode) {
    PREVIEW_MODE_EDIT_WIKITEXT,
    PREVIEW_MODE_EDIT_WIKITEXT_WARNING,
    PREVIEW_MODE_EDIT_WIKITEXT_DISALLOW,
    PREVIEW_MODE_EDIT_WIKITEXT_PREVIEW,
    PREVIEW_MODE_EDIT_WIKITEXT_CAPTCHA
};

@interface EditSaveViewController () <UITextFieldDelegate, UIScrollViewDelegate, PreviewLicenseViewDelegate, WMFCaptchaViewControllerDelegate>

@property (strong, nonatomic) WMFCaptchaViewController *captchaViewController;
@property (strong, nonatomic) IBOutlet UIView *captchaContainer;
@property (strong, nonatomic) IBOutlet UIScrollView *captchaScrollView;
@property (strong, nonatomic) IBOutlet UIView *captchaScrollContainer;

@property (strong, nonatomic) IBOutlet UIView *editSummaryContainer;
@property (strong, nonatomic) UILabel *aboutLabel;
@property (strong, nonatomic) MenuButton *cannedSummary01;
@property (strong, nonatomic) MenuButton *cannedSummary02;
@property (strong, nonatomic) MenuButton *cannedSummary03;
@property (strong, nonatomic) MenuButton *cannedSummary04;
@property (nonatomic) CGFloat borderWidth;
@property (strong, nonatomic) IBOutlet PreviewLicenseView *previewLicenseView;
@property (strong, nonatomic) UIGestureRecognizer *previewLicenseTapGestureRecognizer;
@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet UIView *scrollContainer;
@property (strong, nonatomic) UIBarButtonItem *buttonSave;
@property (strong, nonatomic) UIBarButtonItem *buttonNext;
@property (strong, nonatomic) UIBarButtonItem *buttonX;
@property (strong, nonatomic) UIBarButtonItem *buttonLeftCaret;
@property (strong, nonatomic) NSString *abuseFilterCode;

//@property (nonatomic) BOOL saveAutomaticallyIfSignedIn;

@property (nonatomic) WMFPreviewAndSaveMode mode;

@property (strong, nonatomic) WikiTextSectionUploader *wikiTextSectionUploader;
@property (strong, nonatomic) WMFAuthTokenFetcher *editTokenFetcher;

@end

@implementation EditSaveViewController

- (NSString *)getSummary {
    NSMutableArray *summaryArray = @[].mutableCopy;
    
    if (self.cannedSummary01.enabled) {
        [summaryArray addObject:self.cannedSummary01.text];
    }
    if (self.cannedSummary02.enabled) {
        [summaryArray addObject:self.cannedSummary02.text];
    }
    if (self.cannedSummary03.enabled) {
        [summaryArray addObject:self.cannedSummary03.text];
    }
    
    if (self.cannedSummary04.enabled) {
        if (self.summaryText && (self.summaryText.length > 0)) {
            [summaryArray addObject:self.summaryText];
        }
    }
    
    return [summaryArray componentsJoinedByString:@"; "];
}

- (void)setMode:(WMFPreviewAndSaveMode)mode {
    _mode = mode;
    
    [self updateNavigationForMode:mode];
}

- (void)updateNavigationForMode:(WMFPreviewAndSaveMode)mode {
    UIBarButtonItem *backButton = nil;
    UIBarButtonItem *forwardButton = nil;
    
    switch (mode) {
        case PREVIEW_MODE_EDIT_WIKITEXT:
            backButton = self.buttonLeftCaret;
            forwardButton = self.buttonNext;
            break;
        case PREVIEW_MODE_EDIT_WIKITEXT_WARNING:
            backButton = self.buttonLeftCaret;
            forwardButton = self.buttonSave;
            break;
        case PREVIEW_MODE_EDIT_WIKITEXT_DISALLOW:
            backButton = self.buttonLeftCaret;
            forwardButton = nil;
            break;
        case PREVIEW_MODE_EDIT_WIKITEXT_PREVIEW:
            backButton = self.buttonLeftCaret;
            forwardButton = self.buttonSave;
            break;
        case PREVIEW_MODE_EDIT_WIKITEXT_CAPTCHA:
            backButton = self.buttonX;
            forwardButton = self.buttonSave;
            break;
        default:
            break;
    }
    
    self.navigationItem.leftBarButtonItem = backButton;
    self.navigationItem.rightBarButtonItem = forwardButton;
}

- (void)goBack {
    if (self.mode == PREVIEW_MODE_EDIT_WIKITEXT_WARNING) {
        [self.funnel logAbuseFilterWarningBack:self.abuseFilterCode];
    }
    
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)goForward {
    switch (self.mode) {
        case PREVIEW_MODE_EDIT_WIKITEXT_WARNING:
            [self save];
            [self.funnel logAbuseFilterWarningIgnore:self.abuseFilterCode];
            break;
        case PREVIEW_MODE_EDIT_WIKITEXT_CAPTCHA:
            [self save];
            break;
        default:
            [self save];
            break;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.theme) {
        self.theme = [WMFTheme standard];
    }
    self.wikiTextSectionUploader = [[WikiTextSectionUploader alloc] init];
    self.editTokenFetcher = [[WMFAuthTokenFetcher alloc] init];
    
    self.navigationItem.title = WMFLocalizedStringWithDefaultValue(@"wikitext-preview-save-changes-title", nil, nil, @"Save your changes", @"Title for edit preview screens");
    
    self.previewLicenseView.previewLicenseViewDelegate = self;
    
    self.buttonX = [UIBarButtonItem wmf_buttonType:WMFButtonTypeX target:self action:@selector(goBack)];
    
    self.buttonLeftCaret = [UIBarButtonItem wmf_buttonType:WMFButtonTypeCaretLeft target:self action:@selector(goBack)];
    
    self.buttonSave = [[UIBarButtonItem alloc] initWithTitle:WMFLocalizedStringWithDefaultValue(@"button-publish", nil, nil, @"Publish", @"Button text for publish button used in various places.\n{{Identical|Publish}}") style:UIBarButtonItemStylePlain target:self action:@selector(goForward)];
    
    self.mode = PREVIEW_MODE_EDIT_WIKITEXT_PREVIEW;
    
    self.summaryText = @"";
    
    //self.saveAutomaticallyIfSignedIn = NO;
    
    [self.funnel logPreview];
    
    self.borderWidth = 1.0f / [UIScreen mainScreen].scale;
    
    [self setupEditSummaryContainerSubviews];
    
    [self constrainEditSummaryContainerSubviews];
    
    [self applyTheme:self.theme];
}

- (void)constrainEditSummaryContainerSubviews {
    NSDictionary *views = @{
                            @"aboutLabel": self.aboutLabel,
                            @"cannedSummary01": self.cannedSummary01,
                            @"cannedSummary02": self.cannedSummary02,
                            @"cannedSummary03": self.cannedSummary03,
                            @"cannedSummary04": self.cannedSummary04
                            };
    
    // Tighten up the spacing for 3.5 inch screens.
    CGFloat spaceAboveCC = ([UIScreen mainScreen].bounds.size.height != 480) ? 43 : 4;
    
    NSDictionary *metrics = @{
                              @"buttonHeight": @(48),
                              @"spaceAboveCC": @(spaceAboveCC)
                              };
    
    NSArray *constraints = @[
                             [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[aboutLabel]|"
                                                                     options:0
                                                                     metrics:metrics
                                                                       views:views],
                             [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[cannedSummary01]"
                                                                     options:0
                                                                     metrics:metrics
                                                                       views:views],
                             [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[cannedSummary02]"
                                                                     options:0
                                                                     metrics:metrics
                                                                       views:views],
                             [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[cannedSummary03]"
                                                                     options:0
                                                                     metrics:metrics
                                                                       views:views],
                             [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[cannedSummary04]"
                                                                     options:0
                                                                     metrics:metrics
                                                                       views:views],
                             [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(40)-[aboutLabel]-(5)-[cannedSummary01(buttonHeight)][cannedSummary02(buttonHeight)][cannedSummary03(buttonHeight)][cannedSummary04(buttonHeight)]-(spaceAboveCC)-|"
                                                                     options:0
                                                                     metrics:metrics
                                                                       views:views]
                             ];
    [self.editSummaryContainer addConstraints:[constraints valueForKeyPath:@"@unionOfArrays.self"]];
}

- (void)setupEditSummaryContainerSubviews {
    // Setup the canned edit summary buttons.
    UIColor *color = self.theme.colors.link;
    UIEdgeInsets padding = UIEdgeInsetsMake(6, 10, 6, 10);
    UIEdgeInsets margin = UIEdgeInsetsMake(8, 0, 8, 0);
    CGFloat fontSize = 14.0;
    
    MenuButton * (^setupButton)(NSString *, NSInteger) = ^MenuButton *(NSString *text, WMFCannedSummaryChoices tag) {
        MenuButton *button = [[MenuButton alloc] initWithText:text
                                                     fontSize:fontSize
                                                         bold:NO
                                                        color:color
                                                      padding:padding
                                                       margin:margin];
        button.enabled = NO;
        button.tag = tag;
        [button addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(buttonTapped:)]];
        [self.editSummaryContainer addSubview:button];
        return button;
    };
    
    self.cannedSummary01 = setupButton(WMFLocalizedStringWithDefaultValue(@"edit-summary-choice-fixed-typos", nil, nil, @"Fixed typo", @"Button text for quick 'fixed typos' edit summary selection"), CANNED_SUMMARY_TYPOS);
    self.cannedSummary02 = setupButton(WMFLocalizedStringWithDefaultValue(@"edit-summary-choice-fixed-grammar", nil, nil, @"Fixed grammar", @"Button text for quick 'improved grammar' edit summary selection"), CANNED_SUMMARY_GRAMMAR);
    self.cannedSummary03 = setupButton(WMFLocalizedStringWithDefaultValue(@"edit-summary-choice-linked-words", nil, nil, @"Added links", @"Button text for quick 'link addition' edit summary selection"), CANNED_SUMMARY_LINKS);
    self.cannedSummary04 = setupButton(WMFLocalizedStringWithDefaultValue(@"edit-summary-choice-other", nil, nil, @"Other", @"Button text for quick \"other\" edit summary selection.\n{{Identical|Other}}"), CANNED_SUMMARY_OTHER);
    
    // Setup the canned edit summaries label.
    self.aboutLabel = [[UILabel alloc] init];
    self.aboutLabel.numberOfLines = 0;
    self.aboutLabel.font = [UIFont boldSystemFontOfSize:24.0];
    self.aboutLabel.textColor = self.theme.colors.secondaryText;
    self.aboutLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.aboutLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.aboutLabel.text = WMFLocalizedStringWithDefaultValue(@"edit-summary-title", nil, nil, @"How did you improve the article?", @"Title for edit summary area of the preview page");
    self.aboutLabel.textAlignment = NSTextAlignmentNatural;
    
    [self.editSummaryContainer addSubview:self.aboutLabel];
}

- (void)buttonTapped:(UIGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        MenuButton *tappedButton = (MenuButton *)recognizer.view;
        
        NSString *summaryKey;
        switch (tappedButton.tag) {
            case CANNED_SUMMARY_TYPOS:
                summaryKey = @"typo";
                break;
            case CANNED_SUMMARY_GRAMMAR:
                summaryKey = @"grammar";
                break;
            case CANNED_SUMMARY_LINKS:
                summaryKey = @"links";
                break;
            case CANNED_SUMMARY_OTHER:
                summaryKey = @"other";
                break;
            default:
                NSLog(@"unrecognized button");
        }
        [self.funnel logEditSummaryTap:summaryKey];
        
        switch (tappedButton.tag) {
            case CANNED_SUMMARY_OTHER:
                [self showSummaryOverlay];
                break;
                
            default:
                tappedButton.enabled = !tappedButton.enabled;
                
                break;
        }
    }
}

- (void)showSummaryOverlay {
    EditSummaryViewController *summaryVC = [EditSummaryViewController wmf_initialViewControllerFromClassStoryboard];
    // Set the overlay's text field to self.summaryText so it can display
    // any existing value (in case user taps "Other" again)
    summaryVC.summaryText = self.summaryText;
    __weak typeof(self) weakSelf = self;
    summaryVC.didSaveSummary = ^void(NSString *savedSummary) {
        weakSelf.summaryText = savedSummary;
    };
    [summaryVC applyTheme:self.theme];
    [self presentViewController:[[WMFThemeableNavigationController alloc] initWithRootViewController:summaryVC theme:self.theme] animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    self.captchaScrollView.alpha = 0.0f;
    
    self.captchaViewController = [WMFCaptchaViewController wmf_initialViewControllerFromClassStoryboard];
    self.captchaViewController.captchaDelegate = self;
    [self wmf_addWithChildController:self.captchaViewController andConstrainToEdgesOfContainerView:self.captchaContainer];
    
    self.mode = PREVIEW_MODE_EDIT_WIKITEXT_PREVIEW;
    
    //[self saveAutomaticallyIfNecessary];
    
    // Highlight the "Other" button if the user entered some "other" text.
    self.cannedSummary04.enabled = (self.summaryText.length > 0) ? YES : NO;
    
    if ([[WMFAuthenticationManager sharedInstance] isLoggedIn]) {
        self.previewLicenseView.licenseLoginLabel.userInteractionEnabled = NO;
        self.previewLicenseView.licenseLoginLabel.attributedText = nil;
    } else {
        self.previewLicenseView.licenseLoginLabel.userInteractionEnabled = YES;
    }
    
    self.previewLicenseTapGestureRecognizer =
    [[UITapGestureRecognizer alloc] initWithTarget:self
                                            action:@selector(licenseLabelTapped:)];
    [self.previewLicenseView.licenseLoginLabel addGestureRecognizer:self.previewLicenseTapGestureRecognizer];
    
    [super viewWillAppear:animated];
}

- (void)licenseLabelTapped:(UIGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        // Call if user taps the blue "Log In" text in the CC text.
        //self.saveAutomaticallyIfSignedIn = YES;
        WMFLoginViewController *loginVC = [WMFLoginViewController wmf_initialViewControllerFromClassStoryboard];
        loginVC.funnel = [[WMFLoginFunnel alloc] init];
        [loginVC.funnel logStartFromEdit:self.funnel.editSessionToken];
        [loginVC applyTheme:self.theme];
        UINavigationController *nc = [[WMFThemeableNavigationController alloc] initWithRootViewController:loginVC theme:self.theme];
        [self presentViewController:nc animated:YES completion:nil];
    }
}

- (void)highlightCaptchaSubmitButton:(BOOL)highlight {
    self.buttonSave.enabled = highlight;
}

- (void)viewWillDisappear:(BOOL)animated {
    [[WMFAlertManager sharedInstance] dismissAlert];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"TabularScrollViewItemTapped"
                                                  object:nil];
    
    [self.previewLicenseView.licenseLoginLabel removeGestureRecognizer:self.previewLicenseTapGestureRecognizer];
    
    [super viewWillDisappear:animated];
}

- (void)save {
    //TODO: maybe? if we have credentials, yet the edit token retrieved for an edit
    // is an anonymous token (i think this happens if you try to get an edit token
    // and your login session has expired), need to pop up alert asking user if they
    // want to log in before continuing with their edit
    
    [[WMFAlertManager sharedInstance] showAlert:WMFLocalizedStringWithDefaultValue(@"wikitext-upload-save", nil, nil, @"Publishing...", @"Alert text shown when changes to section wikitext are being published\n{{Identical|Publishing}}") sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
    
    [self.funnel logSaveAttempt];
    if (self.savedPagesFunnel) {
        [self.savedPagesFunnel logEditAttemptWithArticleURL:self.section.article.url];
    }
    
    
    // If fromTitle was set, the section was transcluded, so use the title of the page
    // it was transcluded from.
    NSURL *editURL = self.section.fromURL ? self.section.fromURL : self.section.article.url;
    
    // First try to get an edit token for the page's domain before trying to upload the changes.
    // Only the domain is used to actually fetch the token, the other values are
    // parked in EditTokenFetcher so the actual uploader can have quick read-only
    // access to the exact params which kicked off the token request.
    
    NSURL *url = [[SessionSingleton sharedInstance] urlForLanguage:editURL.wmf_language];
    @weakify(self)
    [self.editTokenFetcher fetchTokenOfType:WMFAuthTokenTypeCsrf
                                    siteURL:url
                                    success:^(WMFAuthToken *result) {
                                        @strongify(self)
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            
                                            [self.wikiTextSectionUploader uploadWikiText:self.wikiText forArticleURL:editURL section:[NSString stringWithFormat:@"%d", self.section.sectionId] summary:[self getSummary] captchaId:self.captchaViewController.captcha.captchaID captchaWord:self.captchaViewController.solution token:result.token completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    if (error) {
                                                        switch (error.code) {
                                                            case WIKITEXT_UPLOAD_ERROR_NEEDS_CAPTCHA: {
                                                                if (self.mode == PREVIEW_MODE_EDIT_WIKITEXT_CAPTCHA) {
                                                                    [self.funnel logCaptchaFailure];
                                                                }
                                                                
                                                                NSURL *captchaUrl = [[NSURL alloc] initWithString:error.userInfo[@"captchaUrl"]];
                                                                NSString *captchaId = error.userInfo[@"captchaId"];
                                                                [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:NO dismissPreviousAlerts:YES tapCallBack:NULL];
                                                                self.captchaViewController.captcha = [[WMFCaptcha alloc] initWithCaptchaID:captchaId captchaURL:captchaUrl];
                                                                [self revealCaptcha];
                                                            } break;
                                                                
                                                            case WIKITEXT_UPLOAD_ERROR_ABUSEFILTER_DISALLOWED:
                                                            case WIKITEXT_UPLOAD_ERROR_ABUSEFILTER_WARNING:
                                                            case WIKITEXT_UPLOAD_ERROR_ABUSEFILTER_OTHER: {
                                                                //NSString *warningHtml = error.userInfo[@"warning"];
                                                                [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
                                                                
                                                                [self wmf_hideKeyboard];
                                                                
                                                                if ((error.code == WIKITEXT_UPLOAD_ERROR_ABUSEFILTER_DISALLOWED)) {
                                                                    self.mode = PREVIEW_MODE_EDIT_WIKITEXT_DISALLOW;
                                                                    self.abuseFilterCode = error.userInfo[@"code"];
                                                                    [self.funnel logAbuseFilterError:self.abuseFilterCode];
                                                                } else {
                                                                    self.mode = PREVIEW_MODE_EDIT_WIKITEXT_WARNING;
                                                                    self.abuseFilterCode = error.userInfo[@"code"];
                                                                    [self.funnel logAbuseFilterWarning:self.abuseFilterCode];
                                                                }
                                                                
                                                                // Hides the license panel. Needed if logged in and a disallow is triggered.
                                                                [[WMFAlertManager sharedInstance] dismissAlert];
                                                                
                                                                AbuseFilterAlertType alertType =
                                                                (error.code == WIKITEXT_UPLOAD_ERROR_ABUSEFILTER_DISALLOWED) ? ABUSE_FILTER_DISALLOW : ABUSE_FILTER_WARNING;
                                                                [self showAbuseFilterAlertOfType:alertType];
                                                            } break;
                                                                
                                                            case WIKITEXT_UPLOAD_ERROR_SERVER:
                                                            case WIKITEXT_UPLOAD_ERROR_UNKNOWN:
                                                                [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
                                                                
                                                                [self.funnel logError:error.localizedDescription]; // @fixme is this right msg?
                                                                break;
                                                                
                                                            default:
                                                                [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
                                                                break;
                                                        }
                                                        return;
                                                    }
                                                    [self.funnel logSavedRevision:[result[@"newrevid"] intValue]];
                                                    [self.delegate editSaveViewControllerDidSave:self];
                                                });
                                            }];
                                        });
                                    }
                                    failure:^(NSError *error) {
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [[WMFAlertManager sharedInstance] showErrorAlert:error sticky:YES dismissPreviousAlerts:YES tapCallBack:NULL];
                                        });
                                    }];
}

- (void)showAbuseFilterAlertOfType:(AbuseFilterAlertType)alertType {
    AbuseFilterAlert *abuseFilterAlert = [[AbuseFilterAlert alloc] initWithType:alertType];
    
    [self.view addSubview:abuseFilterAlert];
    
    NSDictionary *views = @{@"abuseFilterAlert": abuseFilterAlert};
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[abuseFilterAlert]|"
                                                                      options:0
                                                                      metrics:nil
                                                                        views:views]];
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[abuseFilterAlert]|"
                                                                      options:0
                                                                      metrics:nil
                                                                        views:views]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.captchaViewController.solution.length > 0) {
        [self save];
    }
    return YES;
}

- (NSURL *_Nonnull)captchaSiteURL {
    return [SessionSingleton sharedInstance].currentArticleSiteURL;
}

- (void)captchaReloadPushed:(id)sender {
}

- (BOOL)captchaHideSubtitle {
    return YES;
}

- (void)captchaKeyboardReturnKeyTapped {
    [self save];
}

- (void)captchaSolutionChanged:(id)sender solutionText:(nullable NSString *)solutionText {
    [self highlightCaptchaSubmitButton:(solutionText.length == 0) ? NO : YES];
}

- (void)revealCaptcha {
    [self.funnel logCaptchaShown];
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.35];
    [UIView setAnimationTransition:UIViewAnimationTransitionNone
                           forView:self.view
                             cache:NO];
    
    [self.view bringSubviewToFront:self.captchaScrollView];
    
    self.captchaScrollView.alpha = 1.0f;
    self.captchaScrollView.backgroundColor = self.theme.colors.paperBackground;
    
    self.captchaScrollContainer.backgroundColor = [UIColor clearColor];
    self.captchaContainer.backgroundColor = [UIColor clearColor];
    
    [UIView commitAnimations];
    
    self.mode = PREVIEW_MODE_EDIT_WIKITEXT_CAPTCHA;
    
    [self highlightCaptchaSubmitButton:NO];
}

- (void)previewLicenseViewTermsLicenseLabelWasTapped:(PreviewLicenseView *)previewLicenseview {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:WMFLicenses.localizedSaveTermsTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                [self wmf_openExternalUrl:WMFLicenses.saveTermsURL];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WMFLicenses.localizedCCBYSA3Title
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                [self wmf_openExternalUrl:WMFLicenses.CCBYSA3URL];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WMFLicenses.localizedGFDLTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                [self wmf_openExternalUrl:WMFLicenses.GFDLURL];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WMFLocalizedStringWithDefaultValue(@"open-link-cancel", nil, nil, @"Cancel", @"Text for cancel button in popup menu of terms/license link options\n{{Identical|Cancel}}") style:UIAlertActionStyleCancel handler:NULL]];
    [self presentViewController:sheet animated:YES completion:NULL];
}

#pragma mark - WMFThemeable

- (void)applyTheme:(WMFTheme *)theme {
    self.theme = theme;
    if (self.viewIfLoaded == nil) {
        return;
    }
    self.scrollView.backgroundColor = theme.colors.paperBackground;
    self.captchaScrollView.backgroundColor = theme.colors.baseBackground;
    
    [self.previewLicenseView applyTheme:theme];
    
    self.scrollContainer.backgroundColor = theme.colors.paperBackground;
    self.editSummaryContainer.backgroundColor = theme.colors.paperBackground;
    self.captchaContainer.backgroundColor = theme.colors.paperBackground;
    self.captchaScrollContainer.backgroundColor = theme.colors.paperBackground;
}

@end