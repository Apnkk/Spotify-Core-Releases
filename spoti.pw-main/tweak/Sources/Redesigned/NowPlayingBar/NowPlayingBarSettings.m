// The Now playing page of the redesign, under Player (App/Pages.m puts it there): the bar and the
// player behind it.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Player/Visualizer.h"

UIViewController *SGRNowPlayingBarSettingsPage(void) {
    SGModRow *fluidRow = SGWithSymbol(SGPageRow(@"Fluid artwork", ^UIViewController *{ return SGRFluidArtworkSettingsPage(); }), @"drop.halffull");
    SGModRow *visRow = SGWithSymbol(SGPageRow(@"Visualizer", ^UIViewController *{ return SGRVisualizerSettingsPage(); }), @"waveform.path.ecg");
    visRow.value = ^NSString *{ return SGRVisualizerSummary(); };

    return [[SGModPage alloc] initWithTitle:@"Now playing" intro:SGRestartNote sections:@[
        SGSection(@"Mini player", @[
            SGSwitchRow(@"Apple Music style mini player", nil, SGRKeyMiniPlayer),
            SGOptionRow(@"Swap Search and Now Playing", nil, SGRKeyBarSwap),
            SGHideRow(@"Hide the device button", nil, SGRHideBarConnect),
        ]),
        SGSection(@"Player background", @[
            SGSwitchRow(@"Moving background", nil, SGRKeyPlayerMotion),
            fluidRow,
            visRow,
        ]),
    ] footer:nil];
}
