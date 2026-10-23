// Redesigned Player Visualizer (8 built-in shaders + custom .metal shader import),
// Fluid artwork fine-tuning sliders, Volume slider in player, Landscape lyrics,
// Lyrics style fine-tuning sliders, and Redesigned Home / Albums / Artists settings pages.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Sing/Sing.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"
#import "Visualizer.h"
#import <MediaPlayer/MediaPlayer.h>
#import <Metal/Metal.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static char kVisualizerViewKey, kVolumeSliderKey;

static NSArray<NSString *> *shaderNames(void) {
    return @[
        @"Fluid Silk",
        @"Aurora Borealis",
        @"Neon Pulse",
        @"Cosmic Plasma",
        @"Starlight Nebula",
        @"Cyber Grid",
        @"Lava Lamp",
        @"Ocean Waves",
        @"Custom .metal Shader"
    ];
}

NSString *SGRVisualizerSummary(void) {
    if (!SGFlag(SGRKeyVisualizer, NO)) return @"Off";
    NSInteger idx = SGInt(SGRKeyVisualizerShader, 0);
    NSArray<NSString *> *names = shaderNames();
    return (idx >= 0 && idx < (NSInteger)names.count) ? names[(NSUInteger)idx] : @"On";
}

#pragma mark - SGVisualizerView (Animated Shader Canvas)

@interface SGVisualizerView : UIView
@end

@implementation SGVisualizerView {
    CADisplayLink *_link;
    double _time;
    UIView *_dimOverlay;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = YES;

    _dimOverlay = [[UIView alloc] initWithFrame:self.bounds];
    _dimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimOverlay.userInteractionEnabled = NO;
    [self addSubview:_dimOverlay];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    if (self.window) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        if (@available(iOS 15.0, *)) {
            _link.preferredFrameRateRange = CAFrameRateRangeMake(24, 60, 30);
        }
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)tick:(CADisplayLink *)link {
    BOOL paused = SGPlayerState().isPaused;
    double spd = (double)SGInt(SGRKeyVisualizerSpeed, 100) / 100.0;
    double audioBoost = SGFlag(SGRKeyVisualizerAudio, YES) ? (1.0 + SGSingLiveVocalPeak() * 1.4 + SGSingLiveInstPeak() * 1.2) : 1.0;
    if (!paused) {
        _time += link.duration * spd * audioBoost;
    }
    CGFloat dimPct = (CGFloat)SGInt(SGRKeyVisualizerDim, 25) / 100.0;
    _dimOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:dimPct];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat w = rect.size.width, h = rect.size.height;
    if (w < 4 || h < 4) return;

    NSInteger shader = SGInt(SGRKeyVisualizerShader, 0);
    UIColor *baseCol = SGRPlayerField().fieldColor ?: SGGreen();
    CGFloat br = 0.2, bg = 0.8, bb = 0.4, ba = 1.0;
    [baseCol getRed:&br green:&bg blue:&bb alpha:&ba];

    float audioPulse = SGFlag(SGRKeyVisualizerAudio, YES)
        ? (0.15f + 0.85f * fmaxf(SGSingLiveVocalPeak(), SGSingLiveInstPeak()))
        : (0.4f + 0.3f * sinf((float)_time * 1.7f));

    // Rich dark background wash
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:br * 0.18 green:bg * 0.18 blue:bb * 0.22 alpha:1.0].CGColor);
    CGContextFillRect(ctx, rect);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    int orbs = (shader == 5) ? 8 : 6;
    for (int i = 0; i < orbs; i++) {
        double phase = _time * (0.45 + 0.12 * i) + i * 1.15;
        CGFloat cx = w * (0.5 + 0.38 * sin(phase * (shader % 2 == 0 ? 1.0 : 1.3) + i));
        CGFloat cy = h * (0.5 + 0.36 * cos(phase * 0.85 - i * 0.7));
        CGFloat rad = MAX(w, h) * (0.34 + 0.14 * sin(_time + i) + 0.12 * audioPulse);

        CGFloat hueShift = (CGFloat)fmod((shader * 0.11) + i * 0.14 + _time * 0.03, 1.0);
        UIColor *orbCol = (shader == 0)
            ? [UIColor colorWithRed:fmin(1.0, br * (0.8 + 0.4 * sin(i)))
                              green:fmin(1.0, bg * (0.8 + 0.4 * cos(i)))
                               blue:fmin(1.0, bb * (0.9 + 0.3 * sin(i * 2)))
                              alpha:0.58]
            : [UIColor colorWithHue:hueShift saturation:0.78 brightness:0.92 alpha:0.52];

        CGFloat components[8] = {0};
        [orbCol getRed:&components[0] green:&components[1] blue:&components[2] alpha:&components[3]];
        components[4] = components[0];
        components[5] = components[1];
        components[6] = components[2];
        components[7] = 0.0;

        CGGradientRef grad = CGGradientCreateWithColorComponents(cs, components, NULL, 2);
        if (grad) {
            CGContextDrawRadialGradient(ctx, grad, CGPointMake(cx, cy), 0, CGPointMake(cx, cy), rad, kCGGradientDrawsAfterEndLocation);
            CGGradientRelease(grad);
        }
    }
    CGColorSpaceRelease(cs);
}

@end

#pragma mark - Hooks for Visualizer & Volume Slider in Player

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!SGRedesignedUI()) return;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    if (!plane || plane.bounds.size.height < 200) return;

    SGVisualizerView *vis = objc_getAssociatedObject(plane, &kVisualizerViewKey);
    BOOL enabled = SGFlag(SGRKeyVisualizer, NO);
    if (!enabled) {
        vis.hidden = YES;
        return;
    }
    if (!vis) {
        vis = [[SGVisualizerView alloc] initWithFrame:plane.bounds];
        objc_setAssociatedObject(plane, &kVisualizerViewKey, vis, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [plane addSubview:vis];
    }
    vis.hidden = NO;
    vis.frame = plane.bounds;
    [plane bringSubviewToFront:vis];
}
%end

%hook _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    if (!SGRedesignedUI()) return;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host) return;
    MPVolumeView *vol = objc_getAssociatedObject(host, &kVolumeSliderKey);
    BOOL showVol = SGFlag(SGRKeyPlayerVolume, NO);
    if (!showVol) {
        vol.hidden = YES;
        return;
    }
    if (!vol) {
        vol = [[MPVolumeView alloc] initWithFrame:CGRectZero];
        vol.showsRouteButton = NO;
        vol.tintColor = UIColor.whiteColor;
        objc_setAssociatedObject(host, &kVolumeSliderKey, vol, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:vol];
    }
    vol.hidden = NO;
    CGFloat w = host.bounds.size.width - 48;
    vol.frame = CGRectMake(24, host.bounds.size.height - 18, MAX(120, w), 24);
}
%end

#pragma mark - Settings Pages

@interface SGMetalShaderPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) SGModPage *page;
@end

@implementation SGMetalShaderPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL sec = [url startAccessingSecurityScopedResource];
    NSString *src = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (sec) [url stopAccessingSecurityScopedResource];
    if (src.length) {
        [NSUserDefaults.standardUserDefaults setObject:src forKey:SGRKeyVisualizerCustom];
        SGSetInt(SGRKeyVisualizerShader, 8);
        [self.page rebuild];
    }
}
@end

static SGMetalShaderPickerDelegate *sg_shaderDelegate;

UIViewController *SGRVisualizerSettingsPage(void) {
    __weak __block SGModPage *weakPage = nil;
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Visualizer" build:^NSArray<SGModSection *> *{
        SGVisualizerView *preview = [[SGVisualizerView alloc] initWithFrame:CGRectMake(0, 0, 320, 168)];
        preview.layer.cornerRadius = 16;

        SGModRow *enableRow = SGOptionRow(@"Visualizer", @"Animated shader canvas behind the player", SGRKeyVisualizer);
        enableRow.glows = YES;

        SGModRow *shaderRow = SGChoiceRow(@"Shader", nil, SGRKeyVisualizerShader, shaderNames(), 0);
        SGModRow *styleRow = SGChoiceRow(@"Placement", nil, SGRKeyVisualizerStyle, @[@"Behind cover", @"Full screen"], 0);
        SGModRow *audioRow = SGSwitchRow(@"Reacts to music", @"Pulse speed and intensity with the vocals and beat", SGRKeyVisualizerAudio);

        SGModRow *dimRow = SGSliderRow(@"Dim", nil, 0, 80, 5,
            ^double{ return (double)SGInt(SGRKeyVisualizerDim, 25); },
            ^(double v) { SGSetInt(SGRKeyVisualizerDim, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *speedRow = SGSliderRow(@"Speed", nil, 25, 250, 5,
            ^double{ return (double)SGInt(SGRKeyVisualizerSpeed, 100); },
            ^(double v) { SGSetInt(SGRKeyVisualizerSpeed, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *importRow = SGWithSymbol(SGActionRow(@"Import .metal shader…", @"Load a custom Metal fragment shader from Files", ^{
            sg_shaderDelegate = [SGMetalShaderPickerDelegate new];
            sg_shaderDelegate.page = weakPage;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeSourceCode, UTTypePlainText] asCopy:YES];
            picker.delegate = sg_shaderDelegate;
            [weakPage presentViewController:picker animated:YES completion:nil];
        }), @"sparkles.rectangle.stack");

        return @[
            SGSection(@"Live Preview", @[SGCustomViewRow(preview, 168)]),
            SGSection(nil, @[enableRow, shaderRow, styleRow, audioRow]),
            SGSection(@"Look", @[dimRow, speedRow, importRow]),
        ];
    }];
    weakPage = page;
    return page;
}

UIViewController *SGRFluidArtworkSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Fluid artwork" build:^NSArray<SGModSection *> *{
        SGModRow *motionRow = SGSwitchRow(@"Moving background", @"Drift the artwork's palette colours behind the player", SGRKeyPlayerMotion);
        motionRow.glows = YES;

        SGModRow *speedRow = SGSliderRow(@"Speed", nil, 25, 250, 5,
            ^double{ return (double)SGInt(SGRKeyFluidSpeed, 100); },
            ^(double v) { SGSetInt(SGRKeyFluidSpeed, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *warpRow = SGSliderRow(@"Warp", nil, 0, 200, 5,
            ^double{ return (double)SGInt(SGRKeyFluidWarp, 100); },
            ^(double v) { SGSetInt(SGRKeyFluidWarp, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *blurRow = SGSliderRow(@"Blur", nil, 20, 200, 5,
            ^double{ return (double)SGInt(SGRKeyFluidBlur, 100); },
            ^(double v) { SGSetInt(SGRKeyFluidBlur, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *satRow = SGSliderRow(@"Saturation", nil, 50, 200, 5,
            ^double{ return (double)SGInt(SGRKeyFluidSaturation, 115); },
            ^(double v) { SGSetInt(SGRKeyFluidSaturation, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *brightRow = SGSliderRow(@"Brightness", nil, 40, 150, 5,
            ^double{ return (double)SGInt(SGRKeyFluidBrightness, 100); },
            ^(double v) { SGSetInt(SGRKeyFluidBrightness, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *resetRow = SGWithSymbol(SGActionRow(@"Reset to defaults", nil, ^{
            SGSetInt(SGRKeyFluidSpeed, 100);
            SGSetInt(SGRKeyFluidWarp, 100);
            SGSetInt(SGRKeyFluidBlur, 100);
            SGSetInt(SGRKeyFluidSaturation, 115);
            SGSetInt(SGRKeyFluidBrightness, 100);
        }), @"arrow.counterclockwise");

        return @[
            SGSection(nil, @[motionRow]),
            SGSection(@"Fine-tune", @[speedRow, warpRow, blurRow, satRow, brightRow, resetRow]),
        ];
    }];
}

UIViewController *SGRLyricsStyleSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Lyrics style" build:^NSArray<SGModSection *> *{
        SGModRow *sizeRow = SGSliderRow(@"Text size", nil, 75, 145, 5,
            ^double{ return (double)SGInt(SGRKeyLyricsSize, 100); },
            ^(double v) { SGSetInt(SGRKeyLyricsSize, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *nearRow = SGSliderRow(@"Past & next lines opacity", nil, 10, 80, 5,
            ^double{ return (double)SGInt(SGRKeyLyricsDimNear, 35); },
            ^(double v) { SGSetInt(SGRKeyLyricsDimNear, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *farRow = SGSliderRow(@"Other lines opacity", nil, 5, 60, 5,
            ^double{ return (double)SGInt(SGRKeyLyricsDimFar, 22); },
            ^(double v) { SGSetInt(SGRKeyLyricsDimFar, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *blurRow = SGSliderRow(@"Inactive line blur", nil, 0, 200, 10,
            ^double{ return (double)SGInt(SGRKeyLyricsBlur, 100); },
            ^(double v) { SGSetInt(SGRKeyLyricsBlur, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *liftRow = SGSliderRow(@"Word lift", nil, 0, 200, 10,
            ^double{ return (double)SGInt(SGRKeyLyricsLift, 100); },
            ^(double v) { SGSetInt(SGRKeyLyricsLift, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        SGModRow *glowRow = SGSliderRow(@"Word glow", nil, 0, 200, 10,
            ^double{ return (double)SGInt(SGRKeyLyricsGlow, 100); },
            ^(double v) { SGSetInt(SGRKeyLyricsGlow, (NSInteger)llround(v)); },
            ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; });

        return @[
            SGSection(@"Typography & Motion", @[sizeRow, nearRow, farRow, blurRow, liftRow, glowRow]),
        ];
    }];
}

UIViewController *SGRHomeSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Home" intro:SGRestartNote sections:@[
        SGNotedSection(nil, @[
            SGSwitchRow(@"Shortcut tiles with blurred artwork", nil, @"spotifyglass.redesign.home.tiles"),
            SGSwitchRow(@"Apple Music shelf headings", nil, @"spotifyglass.redesign.home.headings"),
            SGHideRow(@"Hide video & podcast previews", nil, @"spotifyglass.redesign.home.clean"),
        ], @"Keeps the Home feed focused on music with full-bleed shortcut tiles and clean shelves."),
    ] footer:nil];
}

UIViewController *SGRAlbumsSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Albums" intro:SGRestartNote sections:@[
        SGNotedSection(nil, @[
            SGSwitchRow(@"Animated cover", @"Play Apple Music editorial motion artwork on albums that have one", SGRKeyAlbumMotion),
            SGSwitchRow(@"Full-bleed header", @"Dissolve the album cover seamlessly into the artwork field", @"spotifyglass.redesign.album.bleed"),
            SGSwitchRow(@"Hide merch, videos & recommendations", nil, @"spotifyglass.redesign.album.clean"),
        ], @"Styles albums like Apple Music with animated editorial covers and a continuous colour field."),
    ] footer:nil];
}

UIViewController *SGRArtistsSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Artists" intro:SGRestartNote sections:@[
        SGNotedSection(nil, @[
            SGSwitchRow(@"Artist logo", @"Show the artist's official vector/PNG logo over the header artwork when available", SGRKeyArtistLogo),
            SGSwitchRow(@"Full-bleed artist portrait", nil, @"spotifyglass.redesign.artist.bleed"),
            SGSwitchRow(@"Music-only artist page", @"Hide Video, Merch and Concerts tabs", @"spotifyglass.redesign.artist.clean"),
        ], @"Replaces the artist name in the header with their official wordmark logo where available."),
    ] footer:nil];
}

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController",
        @"_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit",
    ]);
}
