#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "AutoMix.h"

static char kAutoMixInfoViewKey;

BOOL SGAutoMixEnabled(void) {
    return SGFlag(SGKeyAutoMix, NO);
}

NSString *SGAutoMixSummary(void) {
    if (!SGAutoMixEnabled()) return @"Off";
    NSInteger style = SGInt(SGKeyAutoMixStyle, 0);
    NSInteger len = SGInt(SGKeyAutoMixLength, 6);
    return style == 0 ? @"Beat-matched" : [NSString stringWithFormat:@"%lds", (long)len];
}

static BOOL contextAllowed(NSString *ctxURI) {
    if (!ctxURI.length) return SGFlag(SGKeyAutoMixAutoplay, YES);
    if ([ctxURI containsString:@":playlist:"] || [ctxURI hasPrefix:@"spotify:playlist:"]) {
        return SGFlag(SGKeyAutoMixPlaylists, YES);
    }
    if ([ctxURI containsString:@":collection"] || [ctxURI hasSuffix:@":collection"]) {
        return SGFlag(SGKeyAutoMixLikedSongs, YES);
    }
    if ([ctxURI containsString:@":album:"] || [ctxURI hasPrefix:@"spotify:album:"]) {
        return SGFlag(SGKeyAutoMixAlbums, NO);
    }
    if ([ctxURI containsString:@":artist:"] || [ctxURI containsString:@":station:"] || [ctxURI containsString:@":radio:"]) {
        return SGFlag(SGKeyAutoMixRadio, YES);
    }
    return YES;
}

NSString *SGAutoMixCurrentStatusText(void) {
    if (!SGAutoMixEnabled()) return @"AutoMix off";
    SPTPlayerState *state = SGPlayerState();
    if (!state || !state.track) return @"AutoMix: no player state yet";

    NSString *ctx = SGURIString(state.contextURI);
    BOOL allowed = contextAllowed(ctx);
    NSInteger style = SGInt(SGKeyAutoMixStyle, 0);
    NSInteger blendSec = SGInt(SGKeyAutoMixLength, 6);
    NSString *modeName = !allowed ? @"none (context off)" : (style == 0 ? @"auto · tempo matched" : [NSString stringWithFormat:@"crossfade · %lds", (long)blendSec]);

    NSDictionary *meta = state.track.metadata;
    NSString *fadeInDur = meta[@"audio.fade_in_duration"] ?: [NSString stringWithFormat:@"%ld.0 s", (long)blendSec];
    NSString *fadeOutStart = meta[@"audio.fade_out_start_time"];
    double dur = state.duration;
    double pos = state.position;
    if (!fadeOutStart && dur > blendSec) {
        int remMin = (int)((dur - blendSec) / 60.0);
        double remSec = fmod(dur - blendSec, 60.0);
        fadeOutStart = [NSString stringWithFormat:@"%d:%04.1f", remMin, remSec];
    }

    SPTPlayerTrack *nextTrack = state.future.firstObject;
    NSString *nextTitle = [nextTrack respondsToSelector:@selector(trackTitle)] ? nextTrack.trackTitle : nil;

    int curM = (int)(pos / 60.0), durM = (int)(dur / 60.0);
    double curS = fmod(pos, 60.0), durS = fmod(dur, 60.0);

    NSMutableString *info = [NSMutableString stringWithFormat:@"AutoMix %@\nNow   %d:%04.1f / %d:%04.1f", modeName, curM, curS, durM, durS];
    if (allowed && dur > 0) {
        [info appendFormat:@"\nOut   at %@ · fade %@", fadeOutStart ?: @"–", fadeInDur];
    }
    if (nextTitle.length) {
        [info appendFormat:@"\nNext  \"%@\" · overlap %lds", nextTitle, (long)blendSec];
    } else {
        [info appendString:@"\nNo transition for this song"];
    }
    return info;
}

#pragma mark - Player Info HUD (SGAutoMixInfoView)

@interface SGAutoMixInfoView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSTimer *timer;
- (void)refresh;
@end

@implementation SGAutoMixInfoView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.62];
    self.layer.cornerRadius = 10;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    _label = [UILabel new];
    _label.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
    _label.textColor = [UIColor colorWithWhite:0.95 alpha:0.9];
    _label.numberOfLines = 0;
    [self addSubview:_label];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate];
    _timer = nil;
    if (self.window) {
        [self refresh];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    }
}

- (void)refresh {
    BOOL show = SGAutoMixEnabled() && SGFlag(SGKeyAutoMixInfo, NO);
    self.hidden = !show;
    if (!show) return;
    _label.text = SGAutoMixCurrentStatusText();
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = CGRectInset(self.bounds, 10, 8);
}

@end

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *v = ((UIViewController *)self).viewIfLoaded;
    if (!v) return;
    SGAutoMixInfoView *hud = objc_getAssociatedObject(v, &kAutoMixInfoViewKey);
    BOOL want = SGAutoMixEnabled() && SGFlag(SGKeyAutoMixInfo, NO);
    if (!want) {
        hud.hidden = YES;
        return;
    }
    if (!hud) {
        hud = [[SGAutoMixInfoView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(v, &kAutoMixInfoViewKey, hud, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [v addSubview:hud];
    }
    [hud refresh];
    CGFloat w = v.bounds.size.width - 32;
    hud.frame = CGRectMake(16, v.safeAreaInsets.top + 56, w, 68);
}
%end

#pragma mark - Settings Page

UIViewController *SGAutoMixSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"AutoMix" build:^NSArray<SGModSection *> *{
        SGModRow *master = SGOptionRow(@"AutoMix", @"Blends each song into the next on playlists, albums and radio, beat-matched or as a crossfade.", SGKeyAutoMix);
        master.glows = YES;

        SGModRow *style = SGChoiceRow(@"Style", nil, SGKeyAutoMixStyle, @[@"Beat-matched", @"Crossfade"], 0);
        style.choiceNotes = @[
            @"Matches the beat and tempo where the song has transition data, or crossfades smoothly",
            @"Crossfades every transition over the chosen blend length"
        ];

        SGModRow *length = SGSliderRow(@"Blend length", nil, 1, 12, 1,
            ^double{ return (double)SGInt(SGKeyAutoMixLength, 6); },
            ^(double val) { SGSetInt(SGKeyAutoMixLength, (NSInteger)llround(val)); },
            ^NSString *(double val) { return [NSString stringWithFormat:@"%ld s", (long)llround(val)]; });

        SGModRow *playlists = SGSwitchRow(@"Playlists", nil, SGKeyAutoMixPlaylists);
        SGModRow *liked = SGSwitchRow(@"Liked Songs", nil, SGKeyAutoMixLikedSongs);
        SGModRow *albums = SGOptionRow(@"Albums", nil, SGKeyAutoMixAlbums);
        SGModRow *radio = SGSwitchRow(@"Artists and radio", nil, SGKeyAutoMixRadio);
        SGModRow *queue = SGSwitchRow(@"Queued songs", nil, SGKeyAutoMixQueue);
        SGModRow *autoplay = SGSwitchRow(@"Autoplay", nil, SGKeyAutoMixAutoplay);

        SGModRow *showInfo = SGOptionRow(@"Show info in the player", nil, SGKeyAutoMixInfo);
        SGModRow *statusRow = SGStatRow(@"Status", ^NSString *{
            return SGAutoMixEnabled() ? @"Active" : @"Off";
        });

        return @[
            SGSection(nil, @[master, style, length]),
            SGSection(@"Where", @[playlists, liked, albums, radio, queue, autoplay]),
            SGSection(nil, @[showInfo, statusRow]),
        ];
    }];
}

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController"]);
}
