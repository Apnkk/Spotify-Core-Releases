#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Onboarding.h"
#import "App/About/About.h"
#import "App/Pages.h"
#import "App/Donate/Donate.h"

static const CGFloat kMargin = 24;
static const CGFloat kCardRadius = 20;

#pragma mark - glass

@interface SGGlassView : UIView
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL capsule;
@end

@implementation SGGlassView
static char kPaneKey;
- (void)layoutSubviews {
    [super layoutSubviews];
    UIVisualEffectView *pane = SGGlassFor(self, &kPaneKey);
    pane.frame = self.bounds;
    SGShapeGlass(pane, self.radius, self.capsule);
}
@end

static UIButton *glassButton(NSString *title) {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) config = [UIButtonConfiguration prominentGlassButtonConfiguration];
    else config = [UIButtonConfiguration filledButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.baseBackgroundColor = SGGreen();
    config.baseForegroundColor = UIColor.blackColor;
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]}];
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

static UIButton *actionPill(NSString *title, NSString *symbolName, NSString *url) {
    UIButtonConfiguration *config = [UIButtonConfiguration grayButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.baseForegroundColor = UIColor.whiteColor;
    config.baseBackgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    config.contentInsets = NSDirectionalEdgeInsetsMake(9, 14, 9, 14);
    if (symbolName) {
        config.image = [UIImage systemImageNamed:symbolName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIFontWeightSemibold]];
        config.imagePadding = 6;
    }
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]}];
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        SGOpenURL(url);
    }]];
    return button;
}

#pragma mark - the choice

@interface SGLookCard : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle;
- (void)makeUnavailable:(NSString *)reason;
@end

@implementation SGLookCard {
    SGGlassView *_glass;
    UIImageView *_check;
    UILabel *_line;
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    UIImageView *icon = SGSymbolView(symbol, 18, UIImageSymbolWeightSemibold, 38);
    icon.tintColor = UIColor.whiteColor;
    icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    icon.layer.cornerRadius = 11;
    icon.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    name.textColor = UIColor.whiteColor;

    UILabel *line = [UILabel new];
    line.text = subtitle;
    line.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    line.textColor = SGGrey();
    line.numberOfLines = 0;
    _line = line;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, line]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 3;

    _check = SGSymbolView(@"circle", 22, UIImageSymbolWeightRegular, 26);

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text, _check]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 14;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [text setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1 forAxis:UILayoutConstraintAxisHorizontal];

    _glass = [SGGlassView new];
    _glass.radius = kCardRadius;
    _glass.userInteractionEnabled = NO;
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.layer.borderWidth = 1.0;
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];

    [self addSubview:_glass];
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [icon.widthAnchor constraintEqualToConstant:38],
        [icon.heightAnchor constraintEqualToConstant:38],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
    ]];
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    _check.image = [UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    _check.tintColor = selected ? SGGreen() : [UIColor colorWithWhite:1.0 alpha:0.25];
    self.layer.borderColor = selected ? SGGreen().CGColor : [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.layer.borderWidth = selected ? 2.0 : 1.0;
    self.backgroundColor = selected ? [UIColor colorWithWhite:1.0 alpha:0.10] : [UIColor colorWithWhite:1.0 alpha:0.04];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (self.enabled) self.alpha = highlighted ? 0.6 : 1;
}

- (void)makeUnavailable:(NSString *)reason {
    self.selected = NO;
    self.enabled = NO;
    self.alpha = 0.45;
    _line.text = reason;
    _check.image = [UIImage systemImageNamed:@"lock.fill"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
    _check.tintColor = SGGrey();
}

@end

#pragma mark - the tour

@interface SGOnboardingController : UIViewController
@end

@implementation SGOnboardingController {
    SGLookCard *_redesigned, *_legacy;
    UIView *_communitySection;
    UIButton *_primary;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    return self;
}

- (UIView *)communityNote {
    BOOL isFR = [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"fr"];

    UIImageView *icon = SGSymbolView(@"sparkles", 14, UIImageSymbolWeightSemibold, 18);
    icon.tintColor = SGGreen();

    UILabel *text = [UILabel new];
    text.text = isFR ? @"Liquid Glass est une interface expérimentale signée Ares."
                     : @"Liquid Glass is an experimental interface crafted by Ares.";
    text.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    text.textColor = SGGrey();
    text.numberOfLines = 0;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    line.alignment = UIStackViewAlignmentCenter;
    line.spacing = 8;

    UIButton *gitBtn = actionPill(@"GitHub", @"chevron.left.forwardslash.chevron.right", SGProjectURL);
    UIButton *siteBtn = actionPill(isFR ? @"Site Web" : @"Website", @"globe", SGSiteURL);
    UIButton *discordBtn = actionPill(@"Discord", @"bubble.left.and.bubble.right.fill", SGDiscordURL);

    UIStackView *links = [[UIStackView alloc] initWithArrangedSubviews:@[gitBtn, siteBtn, discordBtn]];
    links.axis = UILayoutConstraintAxisHorizontal;
    links.spacing = 8;
    links.alignment = UIStackViewAlignmentCenter;
    links.distribution = UIStackViewDistributionFillProportionally;

    UIStackView *note = [[UIStackView alloc] initWithArrangedSubviews:@[line, links]];
    note.axis = UILayoutConstraintAxisVertical;
    note.alignment = UIStackViewAlignmentLeading;
    note.spacing = 10;
    note.layoutMargins = UIEdgeInsetsMake(6, 4, 0, 4);
    note.layoutMarginsRelativeArrangement = YES;
    return note;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Fully opaque sleek dark background: Spotify dialogs behind cannot bleed through
    self.view.backgroundColor = [UIColor colorWithRed:14/255.0 green:14/255.0 blue:16/255.0 alpha:1.0];

    BOOL isFR = [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"fr"];

    // App Icon with green ambient glow
    UIView *iconContainer = [UIView new];
    iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    iconContainer.layer.shadowColor = SGGreen().CGColor;
    iconContainer.layer.shadowOffset = CGSizeMake(0, 4);
    iconContainer.layer.shadowRadius = 16;
    iconContainer.layer.shadowOpacity = 0.45;

    UIImageView *iconView = [UIImageView new];
    UIImage *appIcon = nil;
    for (NSString *name in @[@"spotify_logo_01", @"AppIcon60x60"]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
        if (path) { appIcon = [UIImage imageWithContentsOfFile:path]; if (appIcon) break; }
        appIcon = [UIImage imageNamed:name];
        if (appIcon) break;
    }
    iconView.image = appIcon ?: [UIImage systemImageNamed:@"sparkles"];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 18;
    iconView.layer.cornerCurve = kCACornerCurveContinuous;
    iconView.clipsToBounds = YES;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [iconContainer addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [iconContainer.widthAnchor constraintEqualToConstant:72],
        [iconContainer.heightAnchor constraintEqualToConstant:72],
        [iconView.topAnchor constraintEqualToAnchor:iconContainer.topAnchor],
        [iconView.bottomAnchor constraintEqualToAnchor:iconContainer.bottomAnchor],
        [iconView.leadingAnchor constraintEqualToAnchor:iconContainer.leadingAnchor],
        [iconView.trailingAnchor constraintEqualToAnchor:iconContainer.trailingAnchor],
    ]];

    UIView *strip = [UIView new];
    [strip addSubview:iconContainer];
    [NSLayoutConstraint activateConstraints:@[
        [iconContainer.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor],
        [iconContainer.topAnchor constraintEqualToAnchor:strip.topAnchor],
        [iconContainer.bottomAnchor constraintEqualToAnchor:strip.bottomAnchor],
    ]];

    BOOL glass = SGRedesignAvailable();
    UILabel *heading = [UILabel new];
    heading.text = @"Spotify Core";
    heading.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    heading.textColor = UIColor.whiteColor;

    UILabel *subheading = [UILabel new];
    subheading.text = isFR ? @"Choisissez votre interface préférée" : @"Choose your preferred interface";
    subheading.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    subheading.textColor = SGGrey();

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, subheading]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 4;

    _redesigned = [[SGLookCard alloc] initWithSymbol:@"sparkles"
                                               title:isFR ? @"Liquid Glass" : @"Liquid Glass"
                                            subtitle:isFR ? @"Design inspiré d'Apple Music, paroles synchronisées et noir AMOLED."
                                                          : @"Modern Apple Music look, synced lyrics, and pitch-black AMOLED."];

    _legacy = [[SGLookCard alloc] initWithSymbol:@"slider.horizontal.3"
                                           title:isFR ? @"Spotify Classique" : @"Spotify Classic"
                                        subtitle:isFR ? @"Interface Spotify d'origine avec toutes les options et sans pub."
                                                      : @"Original Spotify layout with all features and ad-free playback."];

    for (SGLookCard *card in @[_redesigned, _legacy]) [card addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];

    BOOL redesign = glass && (SGFlag(SGKeyOnboardingSeen, NO) ? SGRedesignedUIStored() : YES);
    _redesigned.selected = redesign;
    _legacy.selected = !redesign;

    if (!glass) {
        [_redesigned makeUnavailable:[NSString stringWithFormat:@"Needs iOS 26. This phone runs iOS %@.", UIDevice.currentDevice.systemVersion]];
        _legacy.enabled = NO;
    }

    _communitySection = [self communityNote];
    _communitySection.hidden = !redesign;

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[strip, titleStack, _redesigned, _legacy, _communitySection]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 14;
    [column setCustomSpacing:24 afterView:strip];
    [column setCustomSpacing:22 afterView:titleStack];
    column.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:column];
    [self.view addSubview:scroll];

    _primary = glassButton(isFR ? @"Commencer l'écoute" : @"Start listening");
    [_primary addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];

    UILabel *footer = [UILabel new];
    footer.text = isFR ? @"Maintenez l'onglet Accueil pour ouvrir les réglages du mod." : @"Hold Home to open Mod Settings.";
    footer.font = [UIFont systemFontOfSize:13];
    footer.textColor = SGGrey();
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:_primary];
    [self.view addSubview:footer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *frame = scroll.frameLayoutGuide, *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_primary.topAnchor constant:-12],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:40],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kMargin],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kMargin],
        [column.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-2 * kMargin],
        [_primary.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [_primary.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [_primary.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12],
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [footer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
    [self refresh];
}

- (void)picked:(SGLookCard *)card {
    _redesigned.selected = card == _redesigned;
    _legacy.selected = card == _legacy;
    BOOL hide = !_redesigned.selected;
    if (_communitySection.hidden != hide) {
        [UIView animateWithDuration:0.25 animations:^{
            self->_communitySection.hidden = hide;
            self->_communitySection.alpha = hide ? 0 : 1;
            [self.view layoutIfNeeded];
        }];
    }
    [self refresh];
}

- (BOOL)needsRestart {
    return _redesigned.selected != SGRedesignedUI();
}

- (void)refresh {
    BOOL isFR = [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"fr"];
    UIButtonConfiguration *config = _primary.configuration;
    NSString *title = isFR ? (self.needsRestart ? @"Redémarrer Spotify" : @"Commencer l'écoute")
                           : (self.needsRestart ? @"Restart Spotify" : @"Start listening");
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]}];
    _primary.configuration = config;
}

- (void)finish {
    SGDonateAfterTour(self.needsRestart);
    SGSetEnabled(SGKeyOnboardingSeen, YES);
    SGSetRedesignedUI(_redesigned.selected);
    if (self.needsRestart) {
        SGRestartSpotify();
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{ SGShowSigningFixIfPending(); }];
}

@end

#pragma mark - entry

static __weak SGOnboardingController *sg_tour;

BOOL SGOnboardingShowing(void) {
    return sg_tour != nil;
}

void SGShowOnboarding(void) {
    if (sg_tour) return;
    UIViewController *root = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { root = window.rootViewController; break; }
        }
    }
    if (!root) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowOnboarding(); });
        return;
    }
    // If Spotify has a modal presented (such as Bluetooth permission, login, etc.), wait for it to be dismissed!
    if (root.presentedViewController != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowOnboarding(); });
        return;
    }
    UIViewController *top = SGTopController();
    if (!top || [top isKindOfClass:UIAlertController.class] || top.isBeingPresented || top.isBeingDismissed) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowOnboarding(); });
        return;
    }
    SGOnboardingController *tour = [SGOnboardingController new];
    sg_tour = tour;
    [top presentViewController:tour animated:YES completion:nil];
}
