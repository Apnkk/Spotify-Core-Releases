// Settings: a Mod Settings row at the end of Spotify's settings list opens the mod's own page.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Native/Home/Home.h"
#import "Shared/Privacy/Privacy.h"
#import "Shared/Flags/Flags.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Sing/Sing.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Stats/Stats.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/PlayerSettings.h"
#import "Redesigned/Player/Visualizer.h"
#import "App/About/About.h"
#import "App/About/AppIconSettings.h"
#import "Pages.h"

static const CGFloat kRowHeight = 56;
static char kRowKey, kInsetKey;

static SGModRow *pageRow(NSString *title, NSString *symbol, UIViewController *(^page)(void)) {
    return SGWithSymbol(SGPageRow(title, page), symbol);
}

static UIViewController *modSettingsPage(void) {
    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    BOOL redesigned = SGRedesignedUIStored();

    // 1. Screens & Look
    NSMutableArray<SGModRow *> *screens = [NSMutableArray arrayWithArray:@[
        pageRow(@"Tab bar", @"dock.rectangle", ^UIViewController *{ return SGNavbarPage(); }),
        pageRow(@"Home", @"house", ^UIViewController *{ return redesigned ? SGRHomeSettingsPage() : SGHomeSettingsPage(); }),
        pageRow(@"Player", @"play.circle", ^UIViewController *{ return SGPlayerSettingsPage(); }),
        pageRow(@"Lyrics", @"quote.bubble", ^UIViewController *{ return SGLyricsSettingsPage(); }),
    ]];
    if (redesigned) {
        [screens addObject:pageRow(@"Albums", @"square.stack", ^UIViewController *{ return SGRAlbumsSettingsPage(); })];
        [screens addObject:pageRow(@"Artists", @"music.mic", ^UIViewController *{ return SGRArtistsSettingsPage(); })];
    }

    // 2. Sound & Playback (Sing, Audio effects, Spatial voice, AutoMix)
    SGModRow *singRow = pageRow(@"Sing", @"mic.fill", ^UIViewController *{ return SGSingSettingsPage(); });
    singRow.value = ^NSString *{ return SGSingSummary(); };

    SGModRow *audioEffects = pageRow(@"Audio effects", @"slider.vertical.3", ^UIViewController *{ return SGDSPSettingsPage(); });
    audioEffects.value = ^NSString *{ return SGDSPSummary(); };

    SGModRow *spatialVoice = pageRow(@"Spatial voice", @"person.wave.2.fill", ^UIViewController *{ return SGSpatialVoiceSettingsPage(); });
    spatialVoice.value = ^NSString *{ return SGSpatialVoiceSummary(); };

    SGModRow *autoMix = pageRow(@"AutoMix", @"waveform.path.ecg.rectangle", ^UIViewController *{ return SGAutoMixSettingsPage(); });
    autoMix.value = ^NSString *{ return SGAutoMixSummary(); };

    NSArray<SGModRow *> *soundRows = @[singRow, audioEffects, spatialVoice, autoMix];

    // 3. Device & Experience (Live Activity, AirPods gestures, Listening stats, Lock screen, Vibrations, Local files)
    NSMutableArray<SGModRow *> *deviceRows = [NSMutableArray array];
    if (@available(iOS 17.0, *)) {
        SGModRow *liveActivity = pageRow(@"Live Activity", @"platter.filled.top.iphone", ^UIViewController *{ return SGLiveActivitySettingsPage(); });
        liveActivity.value = ^NSString *{ return SGLiveActivitySummary(); };
        [deviceRows addObject:liveActivity];
    }
    SGModRow *headGestures = pageRow(@"AirPods gestures", @"airpodspro", ^UIViewController *{ return SGHeadGesturesSettingsPage(); });
    headGestures.value = ^NSString *{ return SGHeadGesturesSummary(); };
    [deviceRows addObject:headGestures];

    SGModRow *statsRow = pageRow(@"Listening stats", @"chart.bar.fill", ^UIViewController *{ return SGStatsSettingsPage(); });
    statsRow.value = ^NSString *{ return SGStatsSummary(); };
    [deviceRows addObject:statsRow];

    [deviceRows addObject:pageRow(@"Lock screen", @"lock", ^UIViewController *{ return SGLockScreenWidgetPage(); })];

    SGModRow *vibrationsRow = pageRow(@"Vibrations", @"iphone.radiowaves.left.and.right", ^UIViewController *{ return SGVibrationsSettingsPage(); });
    vibrationsRow.value = ^NSString *{ return SGVibrationsSummary(); };
    [deviceRows addObject:vibrationsRow];

    [deviceRows addObject:pageRow(@"Local files", @"folder.badge.gearshape", ^UIViewController *{ return SGLocalFilesEditorPage(); })];

    // 4. Privacy, Labs, Flags & Mod
    SGModRow *mod = pageRow(@"Mod", @"info.circle", ^UIViewController *{ return SGAboutPage(); });
    mod.value = ^NSString *{ return @(SG_VERSION); };

    [sections addObjectsFromArray:@[
        SGAppearanceSection(),
        SGSection(@"Screens", screens),
        SGSection(@"Sound & Mixing", soundRows),
        SGSection(@"Experience", deviceRows),
        SGSection(nil, @[
            pageRow(@"Privacy & clutter", @"hand.raised", ^UIViewController *{ return SGPrivacySettingsPage(); }),
            pageRow(@"Labs", @"testtube.2", ^UIViewController *{ return SGLabsPage(); }),
        ]),
        SGSection(nil, @[
            pageRow(@"All flags", @"flag", ^UIViewController *{ return SGAllFlagsPage(); }),
            mod,
        ]),
        SGSection(@"Icône de l'application", @[
            SGAppIconRow(),
        ]),
    ]];
    return [[SGModPage alloc] initWithTitle:@"Spotify Core By Ares" intro:nil sections:sections footer:@"Modified by Ares — Spotify Lifetime Edition (v0.51.0)"];
}

#pragma mark - row in the settings list and the side drawer

@interface SGModSettingsRow : UIControl
@property (nonatomic) BOOL drawer;
@end

@implementation SGModSettingsRow {
    UIImageView *_icon;
    UILabel *_title;
    UIImageView *_chevron;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _icon = SGSymbolView(@"slider.horizontal.3", 20, UIImageSymbolWeightRegular, 24);
    _title = [UILabel new];
    _title.text = @"Spotify Core By Ares";
    _title.textColor = UIColor.whiteColor;
    _chevron = SGSymbolView(@"chevron.right", 11, UIImageSymbolWeightSemibold, 12);
    for (UIView *v in @[_icon, _title, _chevron]) [self addSubview:v];
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _title.font = SGTitleFont();
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height, lead = self.drawer ? 4 : 0;
    _icon.frame = CGRectMake(12 + lead, (height - 24) / 2, 24, 24);
    _title.frame = CGRectMake(48 + lead, 0, width - 96, height);
    _chevron.frame = CGRectMake(width - 24, (height - 12) / 2, 12, 12);
    _chevron.hidden = self.drawer;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}

static UINavigationController *navigationIn(UIViewController *page) {
    if ([page isKindOfClass:UINavigationController.class]) return (UINavigationController *)page;
    for (UIViewController *child in page.childViewControllers) {
        UINavigationController *found = navigationIn(child);
        if (found) return found;
    }
    return nil;
}

- (void)open {
    UIViewController *owner = nil;
    for (UIResponder *r = self; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UIViewController *presenting = self.drawer ? owner.presentingViewController : nil;
    if (!presenting) {
        SGShowPage(owner, modSettingsPage());
        return;
    }
    [presenting dismissViewControllerAnimated:YES completion:^{
        SGShowPage(navigationIn(presenting).topViewController ?: presenting, modSettingsPage());
    }];
}

@end

void SGOpenModSettings(UIView *source) {
    UIViewController *owner = nil;
    for (UIResponder *r = source; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UINavigationController *nav = nil;
    for (UIViewController *page = owner; page && !nav; page = page.parentViewController) nav = navigationIn(page);
    SGShowPage(nav.topViewController ?: SGTopController(), modSettingsPage());
}

__attribute__((visibility("default"))) void SGOpenModSettingsDirect(UIViewController *presenting) {
    if (!presenting) presenting = SGTopController();
    UINavigationController *nav = navigationIn(presenting);
    SGShowPage(nav.topViewController ?: presenting, modSettingsPage());
}

static void placeRow(UICollectionView *list, SGModSettingsRow *row) {
    SGAdoptFonts(list, row);
    CGFloat bottom = list.contentSize.height;
    row.hidden = !row.drawer && bottom <= 0;
    row.frame = CGRectMake(0, row.drawer ? -kRowHeight : bottom, list.bounds.size.width, kRowHeight);

    UIEdgeInsets inset = list.contentInset;
    NSValue *applied = objc_getAssociatedObject(list, &kInsetKey);
    if (applied && UIEdgeInsetsEqualToEdgeInsets(inset, applied.UIEdgeInsetsValue)) return;
    if (row.drawer) inset.top += kRowHeight;
    else inset.bottom += kRowHeight;
    objc_setAssociatedObject(list, &kInsetKey, [NSValue valueWithUIEdgeInsets:inset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.contentInset = inset;
}

static UIViewController *settingsListIn(UIViewController *page, Class kind) {
    if ([page isKindOfClass:kind]) return page;
    for (UIViewController *child in page.childViewControllers) {
        UIViewController *found = settingsListIn(child, kind);
        if (found) return found;
    }
    return nil;
}

static BOOL isSettingsRoot(UIViewController *list) {
    UINavigationController *nav = list.navigationController ?: (list.parentViewController ? list.parentViewController.navigationController : nil);
    if (!nav) return YES;
    for (UIViewController *page in nav.viewControllers) {
        UIViewController *found = settingsListIn(page, list.class);
        if (found) return found == list;
    }
    return YES;
}

%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    BOOL root = isSettingsRoot((UIViewController *)self);
    SGForEachView(((UIViewController *)self).view, ^(UIView *sub) {
        if (![sub isKindOfClass:UICollectionView.class]) return;
        SGModSettingsRow *row = objc_getAssociatedObject(sub, &kRowKey);
        if (!root) {
            [row removeFromSuperview];
            objc_setAssociatedObject(sub, &kRowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        if (row) return;
        row = [[SGModSettingsRow alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(sub, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sub addSubview:row];
    });
}
%end

%hook _TtC23SideDrawer_ListPageImpl18ListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    SGForEachView(((UIViewController *)self).view, ^(UIView *v) {
        if (![v isKindOfClass:UICollectionView.class] || ![NSStringFromClass(v.class) containsString:@"SideDrawerListCollectionView"]) return;
        if (objc_getAssociatedObject(v, &kRowKey)) return;
        SGModSettingsRow *row = [[SGModSettingsRow alloc] initWithFrame:CGRectZero];
        row.drawer = YES;
        objc_setAssociatedObject(v, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [v addSubview:row];
    });
}
%end

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    SGModSettingsRow *row = objc_getAssociatedObject(self, &kRowKey);
    if (row) placeRow(self, row);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC21Settings_PlatformImpl26SettingsListViewController", @"_TtC23SideDrawer_ListPageImpl18ListViewController"]);
    SGRegisterPages();
    SGWatchForUpdates();
}
