#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Player/Visualizer.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "About/AppIconSettings.h"

NSString *const SGRedesignedUIInfo = @"The newest version of Spotify Core, leaning towards Apple Music's Liquid Glass style. It is not compatible with the legacy look's settings.\n\nThe legacy look gives you more freedom, yet still looks like Spotify.";

void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
}

static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Spotify"
        message:on ? @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it." : @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *unavailableRow(void) {
    SGModRow *row = SGStatActionRow(@"Redesigned UI", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Redesigned UI"
            message:[NSString stringWithFormat:@"The redesign is built on Liquid Glass, which iOS 26 draws and no earlier version can. This phone runs iOS %@, so the mod gives you its legacy look instead: Spotify's own screens with everything else the mod adds on them.", UIDevice.currentDevice.systemVersion]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    return SGWithSymbol(row, @"sparkles");
}

static SGModRow *fontRow(void) {
    SGModRow *row = SGWithSymbol(SGPageRow(@"Font", ^UIViewController *{ return SGFontSettingsPage(); }), @"textformat");
    row.value = ^NSString *{ return SGFontSummary(); };
    return row;
}

SGModSection *SGAppearanceSection(void) {
    if (!SGRedesignAvailable()) {
        NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObject:unavailableRow()];
        [rows addObjectsFromArray:SGNativeAppearanceRows()];
        [rows addObject:fontRow()];
        [rows addObject:SGAppIconRow()];
        return SGNotedSection(@"Appearance", rows, @"Changes apply after you restart Spotify.");
    }
    SGModRow *redesign = SGOptionRow(@"Redesigned UI", nil, SGKeyRedesign);
    redesign.glows = YES;
    redesign.info = SGRedesignedUIInfo;
    redesign.changed = ^(BOOL on) {
        SGSetRedesignedUI(on);
        offerRestart(on);
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObject:SGWithSymbol(redesign, @"sparkles")];
    [rows addObjectsFromArray:SGRedesignedUIStored() ? SGRAppearanceRows() : SGNativeAppearanceRows()];
    if (SGRedesignedUIStored()) {
        [rows addObject:SGWithSymbol(SGOptionRow(@"Accent matches now playing", @"Tint controls with the current artwork's dominant colour", SGRKeyAccentFollows), @"eyedropper.halffull")];
    }
    [rows addObject:fontRow()];
    [rows addObject:SGAppIconRow()];
    return SGNotedSection(@"Appearance", rows, @"Changes apply after you restart Spotify.");
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

UIViewController *SGLyricsSettingsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGLyricsSourcesSection(redesigned)];
    if (redesigned) {
        SGModRow *stylePage = SGWithSymbol(SGPageRow(@"Lyrics style", ^UIViewController *{ return SGRLyricsStyleSettingsPage(); }), @"slider.horizontal.below.rectangle");
        SGModRow *landscapeRow = SGWithSymbol(SGSwitchRow(@"Landscape lyrics", @"Side-by-side cover and synced lyrics when rotating iPhone", SGRKeyPlayerLandscape), @"rectangle.split.2x1");
        [sections addObject:SGSection(@"Display", @[
            SGLyricsWordTimingRow(),
            SGRLyricsTextSizesRow(),
            stylePage,
            SGLyricsTranslationLanguageRow(),
            SGLyricsMeaningsRow(),
            landscapeRow,
        ])];
    }
    [sections addObject:SGSection(nil, more)];
    return [[SGModPage alloc] initWithTitle:@"Lyrics" intro:SGRestartNote sections:sections footer:nil];
}

UIViewController *SGPlayerSettingsPage(void) {
    SGModRow *blocked = SGPageRow(@"Blocked artists", ^UIViewController *{ return SGArtistBlockSettingsPage(); });
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : @"Off";
    };
    SGModRow *headGestures = SGWithSymbol(SGPageRow(@"AirPods gestures", ^UIViewController *{ return SGHeadGesturesSettingsPage(); }), @"airpodspro");
    headGestures.value = ^NSString *{ return SGHeadGesturesSummary(); };

    BOOL native = !SGRedesignedUIStored();

    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        SGWithSymbol(SGPageRow(@"Gestures", ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap"),
        headGestures,
        SGWithSymbol(SGPageRow(@"Lyrics", ^UIViewController *{ return SGLyricsSettingsPage(); }), @"quote.bubble"),
        SGWithSymbol(blocked, @"person.crop.circle.badge.xmark"),
    ])];
    NSMutableArray<SGModRow *> *pages = [NSMutableArray array];
    if (native) {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing bar", ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
        [pages addObject:SGWithSymbol(SGPageRow(@"Queue & devices", ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward")];
    } else {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing", ^UIViewController *{ return SGRNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
        [pages addObject:SGWithSymbol(SGPageRow(@"Fluid artwork", ^UIViewController *{ return SGRFluidArtworkSettingsPage(); }), @"drop.halffull")];
        SGModRow *visRow = SGWithSymbol(SGPageRow(@"Visualizer", ^UIViewController *{ return SGRVisualizerSettingsPage(); }), @"waveform.path.ecg");
        visRow.value = ^NSString *{ return SGRVisualizerSummary(); };
        [pages addObject:visRow];
        [pages addObject:SGWithSymbol(SGOptionRow(@"Volume slider in player", @"Show a system volume bar below playback controls", SGRKeyPlayerVolume), @"speaker.wave.3.fill")];
    }
    [pages addObject:SGWithSymbol(SGPageRow(@"Lock screen widget", ^UIViewController *{ return SGLockScreenWidgetPage(); }), @"lock")];
    [pages addObject:SGWithSymbol(SGPageRow(@"Local files (Edit Info)", ^UIViewController *{ return SGLocalFilesEditorPage(); }), @"folder.badge.gearshape")];
    [sections addObject:SGSection(nil, pages)];
    if (native) [sections addObjectsFromArray:SGNativePlayerScreenSections()];
    [sections addObjectsFromArray:SGVibrationsSections()];

    return [[SGModPage alloc] initWithTitle:@"Player" intro:SGRestartNote sections:sections footer:nil];
}
