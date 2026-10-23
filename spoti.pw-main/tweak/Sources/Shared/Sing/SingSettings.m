#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Sing.h"

#pragma mark - Interactive Sing Demo Card

@interface SGRSingDemoView : UIView
@end

@implementation SGRSingDemoView {
    UILabel *_titleLabel;
    UILabel *_lyricLine1;
    UILabel *_lyricLine2;
    UIButton *_micBtn;
    UISlider *_vocalSlider;
    UILabel *_levelBadge;
    CADisplayLink *_link;
    double _phase;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1.0];
    self.layer.cornerRadius = 16;
    self.clipsToBounds = YES;

    _titleLabel = [UILabel new];
    _titleLabel.text = @"SING LIVE MIXER";
    _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    _titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];

    _lyricLine1 = [UILabel new];
    _lyricLine1.text = @"♪ Good morning, look at the valedictorian ♪";
    _lyricLine1.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    _lyricLine1.textColor = UIColor.whiteColor;
    _lyricLine1.numberOfLines = 2;

    _lyricLine2 = [UILabel new];
    _lyricLine2.text = @"20% vocals at the bottom · Original in the middle · Vocals only at the top";
    _lyricLine2.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _lyricLine2.textColor = SGGrey();
    _lyricLine2.numberOfLines = 2;

    _micBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _micBtn.layer.cornerRadius = 18;
    [_micBtn addTarget:self action:@selector(toggleActive) forControlEvents:UIControlEventTouchUpInside];

    _vocalSlider = [UISlider new];
    _vocalSlider.minimumValue = 0.0f;
    _vocalSlider.maximumValue = 1.0f;
    _vocalSlider.value = SGSingVocalLevel();
    _vocalSlider.minimumTrackTintColor = SGGreen();
    _vocalSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    [_vocalSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];

    _levelBadge = [UILabel new];
    _levelBadge.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _levelBadge.textColor = SGGreen();
    _levelBadge.textAlignment = NSTextAlignmentRight;

    for (UIView *v in @[_titleLabel, _lyricLine1, _lyricLine2, _micBtn, _vocalSlider, _levelBadge]) {
        [self addSubview:v];
    }
    [self refreshState];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    if (self.window) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)tick:(CADisplayLink *)link {
    _phase += link.duration;
    float vPeak = SGSingLiveVocalPeak();
    CGFloat alpha = SGSingActive() ? (0.55 + 0.45 * fmax(vPeak, 0.35 * (0.5 + 0.5 * sin(_phase * 3.0)))) : 0.85;
    _lyricLine1.alpha = alpha;
}

- (void)toggleActive {
    SGSetSingActive(!SGSingActive());
    SGSingNotifySettingsChanged();
    [self refreshState];
}

- (void)sliderChanged:(UISlider *)slider {
    SGSetSingVocalLevel(slider.value);
    if (!SGSingActive()) SGSetSingActive(YES);
    SGSingNotifySettingsChanged();
    [self refreshState];
}

- (void)refreshState {
    BOOL on = SGSingActive();
    float lvl = SGSingVocalLevel();
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    [_micBtn setImage:[UIImage systemImageNamed:(on ? @"mic.fill" : @"mic") withConfiguration:cfg] forState:UIControlStateNormal];
    [_micBtn setTitle:(on ? @" Sing On" : @" Sing Off") forState:UIControlStateNormal];
    _micBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _micBtn.tintColor = on ? UIColor.blackColor : UIColor.whiteColor;
    _micBtn.backgroundColor = on ? SGGreen() : [UIColor colorWithWhite:1.0 alpha:0.14];

    if (lvl < 0.42f) {
        int pct = (int)lrintf(20.0f + (lvl / 0.5f) * 80.0f);
        _levelBadge.text = [NSString stringWithFormat:@"Vocals %d%% (Karaoke)", pct];
    } else if (lvl > 0.58f) {
        int instPct = (int)lrintf((1.0f - (lvl - 0.5f) / 0.5f * 0.92f) * 100.0f);
        _levelBadge.text = [NSString stringWithFormat:@"Vocals Only (Inst %d%%)", instPct];
    } else {
        _levelBadge.text = @"Original Mix (100%)";
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _titleLabel.frame = CGRectMake(16, 14, w - 140, 16);
    _micBtn.frame = CGRectMake(w - 116, 10, 100, 32);
    _lyricLine1.frame = CGRectMake(16, 44, w - 32, 42);
    _lyricLine2.frame = CGRectMake(16, 88, w - 32, 32);
    _levelBadge.frame = CGRectMake(16, 124, w - 32, 18);
    _vocalSlider.frame = CGRectMake(16, 144, w - 32, 28);
}

@end

#pragma mark - Spatial Voice 3D Stage Preview

@interface SGRSpatialVoiceScene : UIView
@end

@implementation SGRSpatialVoiceScene {
    CADisplayLink *_link;
    UILabel *_caption;
    double _time;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = [UIColor colorWithRed:0.07 green:0.08 blue:0.11 alpha:1.0];
    self.clipsToBounds = YES;

    _caption = [UILabel new];
    _caption.text = @"Voice in front of you · Follows your head with AirPods";
    _caption.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _caption.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    _caption.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_caption];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    if (self.window) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)tick:(CADisplayLink *)link {
    _time += link.duration;
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _caption.frame = CGRectMake(12, self.bounds.size.height - 28, self.bounds.size.width - 24, 20);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat w = rect.size.width, h = rect.size.height;
    CGPoint listener = CGPointMake(w * 0.5, h * 0.66);

    float dist = (float)SGInt(SGKeySpatialVoiceDistance, 35) / 100.0f;
    float room = (float)SGInt(SGKeySpatialVoiceRoom, 30) / 100.0f;
    float widthPct = (float)SGInt(SGKeySpatialVoiceWidth, 115) / 100.0f;
    float yaw = SGSpatialVoiceRelativeYaw();
    float vPeak = fmaxf(0.25f, SGSingLiveVocalPeak());

    // Room acoustic rings
    for (int r = 1; r <= 3; r++) {
        CGFloat rad = (42.0 + r * 26.0) * (0.65 + 0.55 * room);
        CGContextSetStrokeColorWithColor(ctx, [SGGreen() colorWithAlphaComponent:(0.10 + 0.12 * room) / r].CGColor);
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(listener.x - rad, listener.y - rad * 0.72, rad * 2, rad * 1.44));
    }

    // Instruments stereo width arc
    CGFloat arcRadius = 56.0 + 38.0 * dist;
    CGFloat halfSpread = (M_PI * 0.42) * widthPct;
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:0.45].CGColor);
    CGContextSetLineWidth(ctx, 4.0);
    CGContextAddArc(ctx, listener.x, listener.y, arcRadius, -M_PI_2 - halfSpread, -M_PI_2 + halfSpread, 0);
    CGContextStrokePath(ctx);

    // Vocal orb in front of listener (offset by relative head yaw)
    CGFloat vocalDist = 34.0 + dist * 62.0;
    CGPoint vocalPos = CGPointMake(listener.x - sin(yaw) * vocalDist, listener.y - cos(yaw) * vocalDist * 0.85);
    CGFloat pulse = 14.0 + 6.0 * vPeak + 2.5 * sin(_time * 4.0);
    CGContextSetFillColorWithColor(ctx, [SGGreen() colorWithAlphaComponent:0.26].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(vocalPos.x - pulse * 1.5, vocalPos.y - pulse * 1.5, pulse * 3.0, pulse * 3.0));
    CGContextSetFillColorWithColor(ctx, SGGreen().CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(vocalPos.x - 9, vocalPos.y - 9, 18, 18));

    // Listener head icon at center
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.95 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(listener.x - 10, listener.y - 10, 20, 20));
}

@end

#pragma mark - Pages

UIViewController *SGSingSettingsPage(void) {
    SGRSingDemoView *demo = [[SGRSingDemoView alloc] initWithFrame:CGRectMake(0, 0, 320, 182)];
    SGModRow *demoRow = SGCustomViewRow(demo, 182);

    SGModRow *enableRow = SGSwitchRow(@"Sing", nil, SGKeySing);
    enableRow.glows = YES;
    enableRow.changed = ^(BOOL on) {
        if (!on) SGSetSingActive(NO);
        SGSingNotifySettingsChanged();
    };

    SGModRow *modelRow = SGChoiceRow(@"Voice model", nil, SGKeySingLight, @[@"Full model", @"Light model"], 0);
    modelRow.choiceNotes = @[
        @"The full model: cleanest vocal & instrument separation, runs locally on this iPhone",
        @"The light model, for older iPhones: lower CPU & battery usage"
    ];
    modelRow.chosen = ^(NSInteger idx) { SGSingNotifySettingsChanged(); };

    SGModRow *heatRow = SGOptionRow(@"Ignore heat warnings", nil, SGKeySingIgnoreHeat);
    SGModRow *memRow = SGOptionRow(@"Ignore memory warnings", nil, SGKeySingIgnoreMemory);

    NSArray<SGModSection *> *sections = @[
        SGSection(@"Interactive Preview", @[demoRow]),
        SGNotedSection(nil, @[enableRow, modelRow], @"Turns the song's vocals down to sing over, or its instruments down to leave only the vocals, from the microphone in the lyrics and player."),
        SGSection(@"Performance", @[heatRow, memRow]),
    ];
    return [[SGModPage alloc] initWithTitle:@"Sing" intro:nil sections:sections footer:nil];
}

UIViewController *SGSpatialVoiceSettingsPage(void) {
    SGRSpatialVoiceScene *scene = [[SGRSpatialVoiceScene alloc] initWithFrame:CGRectMake(0, 0, 320, 210)];
    SGModRow *sceneRow = SGCustomViewRow(scene, 210);

    SGModRow *spatialSwitch = SGOptionRow(@"Spatial voice", @"Keeps the voice in one place as you turn your head.", SGKeySpatialVoice);
    spatialSwitch.glows = YES;
    spatialSwitch.changed = ^(BOOL on) {
        if (on && !SGSingEnabled()) SGSetEnabled(SGKeySing, YES);
        SGSingNotifySettingsChanged();
    };

    SGModRow *distRow = SGSliderRow(@"Distance", nil, 0, 100, 5,
        ^double{ return (double)SGInt(SGKeySpatialVoiceDistance, 35); },
        ^(double val) { SGSetInt(SGKeySpatialVoiceDistance, (NSInteger)llround(val)); SGSingNotifySettingsChanged(); },
        ^NSString *(double val) { return [NSString stringWithFormat:@"%.0f%%", val]; });

    SGModRow *roomRow = SGSliderRow(@"Room", nil, 0, 100, 5,
        ^double{ return (double)SGInt(SGKeySpatialVoiceRoom, 30); },
        ^(double val) { SGSetInt(SGKeySpatialVoiceRoom, (NSInteger)llround(val)); SGSingNotifySettingsChanged(); },
        ^NSString *(double val) { return [NSString stringWithFormat:@"%.0f%%", val]; });

    SGModRow *backRow = SGChoiceRow(@"Back in front", nil, SGKeySpatialVoiceBack, @[@"Off", @"Slow", @"Medium", @"Fast"], 1);
    backRow.chosen = ^(NSInteger idx) { SGSingNotifySettingsChanged(); };

    SGModRow *widthRow = SGSliderRow(@"Instruments width", nil, 50, 150, 5,
        ^double{ return (double)SGInt(SGKeySpatialVoiceWidth, 115); },
        ^(double val) { SGSetInt(SGKeySpatialVoiceWidth, (NSInteger)llround(val)); SGSingNotifySettingsChanged(); },
        ^NSString *(double val) { return [NSString stringWithFormat:@"%.0f%%", val]; });

    NSArray<SGModSection *> *sections = @[
        SGSection(@"Stage Preview", @[sceneRow]),
        SGNotedSection(nil, @[spatialSwitch], @"Spatial voice places the separated vocal stem in 3D space in front of you and tracks your head movement with AirPods Pro, AirPods Max, or Beats."),
        SGSection(@"Sound", @[distRow, roomRow, backRow, widthRow]),
    ];
    return [[SGModPage alloc] initWithTitle:@"Spatial voice" intro:nil sections:sections footer:nil];
}
