#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Appearance.h"

static void applyNativeAccentHex(NSInteger hex) {
    SGSetInt(SGKeyAccent, (int)hex);
}

// Going back to Spotify's green is offered only once a colour of the mod's is set, so a stray tap
// cannot wipe it.
static void chooseAccent(void) {
    UIViewController *top = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"UI Themes & Accent Colours" message:@"Choose a streaming style theme or pick a custom colour" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"💜 Deezer Neon Flow" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0xA238FF); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🍎 Apple Music Crimson" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0xFA243C); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🟣 Ares Electric Purple" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0x9D4EDD); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🟢 Spotify Classic Green" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0x1DB954); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🔵 Cyberpunk Cyan" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0x00F0FF); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🔴 Sunset Crimson" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0xFF2A6D); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🟡 Electric Gold" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { applyNativeAccentHex(0xFFD700); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"🎨 Pick custom colour..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGPickAccent(); }]];
    if (SGAccentColor()) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Reset to default" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { SGSetInt(SGKeyAccent, -1); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:sheet animated:YES completion:nil];
}

// The native look's rows of the Appearance card (App/Pages.m).
NSArray<SGModRow *> *SGNativeAppearanceRows(void) {
    return @[
        SGWithSymbol(SGOptionRow(@"AMOLED background", nil, SGKeyAmoled), @"moon"),
        SGWithSymbol(SGStatActionRow(@"Accent colour", nil, ^NSString *{ return SGAccentLabel(); }, ^{ chooseAccent(); }), @"paintpalette"),
    ];
}
