// The Vibrations page & sections, with an interactive haptic wave preview, Controls strength,
// Music Haptics strength, Follows mode, and In the Background support.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Haptics.h"

static NSString *const kMusicHapticsInfo = @"The iPhone taps along with the drums and rumbles under the bass of whatever Spotify is playing, worked out from the sound as it plays, much like Music Haptics in Apple Music.";

static NSArray<NSString *> *followsNames(void) {
    return @[@"Everything", @"Beat", @"Bass"];
}

static NSArray<NSString *> *followsNotes(void) {
    return @[@"A tap on each kick and snare, and a rumble under the bass",
             @"A tap on each kick and snare, no rumble",
             @"A tap on each kick, and a rumble under the bass"];
}

static void strengthRange(NSString *key, NSInteger *minimum, NSInteger *maximum) {
    BOOL music = [key isEqualToString:SGKeyMusicStrength];
    *minimum = music ? SGMusicStrengthMin : SGControlStrengthMin;
    *maximum = music ? SGMusicStrengthMax : SGControlStrengthMax;
}

double SGHapticsStrength(NSString *key) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return MAX(minimum, MIN(maximum, SGInt(key, 100))) / 100.0;
}

SGMusicFollows SGMusicHapticsFollows(void) {
    NSInteger follows = SGInt(SGKeyMusicFollows, SGMusicFollowsEverything);
    return follows >= SGMusicFollowsEverything && follows <= SGMusicFollowsBass ? (SGMusicFollows)follows : SGMusicFollowsEverything;
}

static SGModRow *strengthRow(NSString *key, void (^changed)(void)) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return SGSliderRow(@"Strength", nil, minimum, maximum, SGStrengthStep,
        ^double { return SGHapticsStrength(key) * 100; },
        ^(double value) {
            SGSetInt(key, lround(value));
            if (changed) changed();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });
}

#pragma mark - Interactive Vibrations Scene

@interface SGVibrationsScene : UIView
@end

@implementation SGVibrationsScene {
    CADisplayLink *_link;
    double _phase;
    double _burst;
    UILabel *_caption;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0];
    self.clipsToBounds = YES;

    _caption = [UILabel new];
    _caption.text = @"Tap anywhere to test Taptic Engine response";
    _caption.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _caption.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    _caption.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_caption];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    [self addGestureRecognizer:tap];
    return self;
}

- (void)tapped {
    _burst = 1.0;
    SGPlayFeedback(SGFeedbackPlay);
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
    _phase += link.duration * 3.8;
    _burst = fmax(0.0, _burst - link.duration * 2.2);
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _caption.frame = CGRectMake(12, self.bounds.size.height - 26, self.bounds.size.width - 24, 18);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGFloat w = rect.size.width, h = rect.size.height - 24;
    CGFloat midY = h * 0.52;
    int bars = 28;
    CGFloat spacing = (w - 40) / bars;
    double factor = SGHapticsStrength(SGKeyMusicStrength);
    for (int i = 0; i < bars; i++) {
        double norm = (double)i / (double)(bars - 1) * 2.0 - 1.0;
        double env = exp(-norm * norm * 2.5);
        double wave = 0.35 + 0.65 * fabs(sin(_phase + i * 0.42));
        CGFloat barH = (CGFloat)((14.0 + 44.0 * env * wave * (0.65 + 0.35 * factor) + 28.0 * _burst * env));
        CGRect barRect = CGRectMake(20 + i * spacing + 2, midY - barH * 0.5, MAX(3.0, spacing - 4), barH);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:2.0];
        UIColor *col = [SGGreen() colorWithAlphaComponent:(CGFloat)(0.38 + 0.55 * env)];
        [col setFill];
        [path fill];
    }
}

@end

NSArray<SGModSection *> *SGVibrationsSections(void) {
    SGModRow *controls = SGSwitchRow(@"Controls", @"Tactile feedback on play, skip, scrub and buttons", SGKeyControlHaptics);
    SGModRow *controlStrength = strengthRow(SGKeyControlStrength, ^{
        SGPlayFeedback(SGFeedbackAdd);
    });
    controlStrength.visible = ^BOOL { return SGEnabled(SGKeyControlHaptics); };

    SGModRow *music = SGOptionRow(@"Music Haptics", @"Taps on the drums and rumbles under the bass", SGKeyMusicHaptics);
    music.info = kMusicHapticsInfo;
    music.changed = ^(BOOL on) { SGSetMusicHapticsEnabled(on); };
    BOOL (^musicOn)(void) = ^BOOL { return SGFlag(SGKeyMusicHaptics, NO); };
    SGModRow *musicStrength = strengthRow(SGKeyMusicStrength, ^{ SGMusicHapticsSettingsChanged(); });
    musicStrength.visible = musicOn;
    SGModRow *follows = SGChoiceRow(@"Follows", nil, SGKeyMusicFollows, followsNames(), SGMusicFollowsEverything);
    follows.choiceNotes = followsNotes();
    follows.chosen = ^(NSInteger index) { SGMusicHapticsSettingsChanged(); };
    follows.visible = musicOn;
    SGModRow *bgRow = SGOptionRow(@"In the Background", @"Keep Music Haptics active while the screen is locked or another app is open", SGKeyMusicHapticsBackground);
    bgRow.changed = ^(BOOL on) { SGMusicHapticsSettingsChanged(); };
    bgRow.visible = musicOn;

    return @[
        SGSection(@"Vibrations", @[SGWithSymbol(controls, @"hand.tap"), controlStrength]),
        SGSection(nil, @[SGWithSymbol(music, @"waveform"), musicStrength, follows, bgRow]),
    ];
}

NSString *SGVibrationsSummary(void) {
    BOOL c = SGEnabled(SGKeyControlHaptics);
    BOOL m = SGFlag(SGKeyMusicHaptics, NO);
    if (c && m) return @"Controls & Music";
    if (m) return @"Music";
    if (c) return @"Controls";
    return @"Off";
}

UIViewController *SGVibrationsSettingsPage(void) {
    SGVibrationsScene *scene = [[SGVibrationsScene alloc] initWithFrame:CGRectMake(0, 0, 320, 136)];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[SGCustomViewRow(scene, 136)])];
    [sections addObjectsFromArray:SGVibrationsSections()];
    return [[SGModPage alloc] initWithTitle:@"Vibrations" intro:nil sections:sections footer:nil];
}
