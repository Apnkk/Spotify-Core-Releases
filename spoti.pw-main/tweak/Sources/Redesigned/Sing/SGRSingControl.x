// Apple Music-style Sing microphone button & vertical vocal slider capsule inside SGRKaraokeView.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/Sing.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"

static char kSingControlKey;

@interface SGRSingControl : UIView
- (void)refreshState;
@end

@implementation SGRSingControl {
    UIVisualEffectView *_glass;
    UIButton *_micBtn;
    UIButton *_spatialBtn;
    UIView *_trackBg;
    UIView *_trackFill;
    BOOL _expanded;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _glass.layer.cornerRadius = 22;
    _glass.layer.cornerCurve = kCACornerCurveContinuous;
    _glass.clipsToBounds = YES;
    [self addSubview:_glass];

    _trackBg = [UIView new];
    _trackBg.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    _trackBg.layer.cornerRadius = 5;
    _trackBg.clipsToBounds = YES;
    _trackBg.alpha = 0;

    _trackFill = [UIView new];
    _trackFill.backgroundColor = UIColor.whiteColor;
    [_trackBg addSubview:_trackFill];
    [_glass.contentView addSubview:_trackBg];

    _micBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_micBtn addTarget:self action:@selector(micTapped) forControlEvents:UIControlEventTouchUpInside];
    [_glass.contentView addSubview:_micBtn];

    _spatialBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_spatialBtn addTarget:self action:@selector(spatialTapped) forControlEvents:UIControlEventTouchUpInside];
    _spatialBtn.alpha = 0;
    [_glass.contentView addSubview:_spatialBtn];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshState) name:@"SGSingStateDidChangeNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshState) name:@"spotifyglass.singSpatialChanged" object:nil];
    [self refreshState];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)micTapped {
    BOOL next = !SGSingActive();
    SGSetSingActive(next);
    _expanded = next;
    SGSingNotifySettingsChanged();
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self refreshState];
        [self.superview setNeedsLayout];
        [self.superview layoutIfNeeded];
    } completion:nil];
}

- (void)spatialTapped {
    BOOL on = !SGSpatialVoiceEnabled();
    SGSetEnabled(SGKeySpatialVoice, on);
    SGSingNotifySettingsChanged();
    [self refreshState];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (!SGSingActive()) {
        SGSetSingActive(YES);
        _expanded = YES;
    }
    CGPoint loc = [pan locationInView:_glass];
    CGFloat top = 46.0, bottom = _glass.bounds.size.height - 46.0;
    CGFloat span = MAX(1.0, bottom - top);
    float level = (float)(1.0 - (loc.y - top) / span);
    SGSetSingVocalLevel(fmaxf(0.0f, fminf(1.0f, level)));
    SGSingNotifySettingsChanged();
    [self setNeedsLayout];
}

- (CGSize)preferredSize {
    if (!SGSingEnabled()) return CGSizeZero;
    return _expanded && SGSingActive() ? CGSizeMake(44, 186) : CGSizeMake(44, 44);
}

- (void)refreshState {
    self.hidden = !SGSingEnabled();
    BOOL active = SGSingActive();
    if (!active) _expanded = NO;
    BOOL spatial = SGSpatialVoiceEnabled();

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [_micBtn setImage:[UIImage systemImageNamed:(active ? @"mic.fill" : @"mic") withConfiguration:cfg] forState:UIControlStateNormal];
    _micBtn.tintColor = active ? SGGreen() : UIColor.whiteColor;

    UIImageSymbolConfiguration *scfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    [_spatialBtn setImage:[UIImage systemImageNamed:@"person.spatialaudio.3d.fill" withConfiguration:scfg] forState:UIControlStateNormal];
    _spatialBtn.tintColor = spatial ? SGGreen() : [UIColor colorWithWhite:1.0 alpha:0.55];

    _trackBg.alpha = (_expanded && active) ? 1.0 : 0.0;
    _spatialBtn.alpha = (_expanded && active) ? 1.0 : 0.0;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glass.frame = self.bounds;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _micBtn.frame = CGRectMake(0, h - 44, w, 44);
    if (_expanded && h > 100) {
        _spatialBtn.frame = CGRectMake(0, 2, w, 38);
        CGFloat trackH = h - 90;
        _trackBg.frame = CGRectMake((w - 10) * 0.5, 42, 10, trackH);
        CGFloat fillH = trackH * SGSingVocalLevel();
        _trackFill.frame = CGRectMake(0, trackH - fillH, 10, fillH);
        _trackFill.backgroundColor = SGGreen();
    }
}

@end

%hook SGRKaraokeView
- (void)layoutSubviews {
    %orig;
    UIView *host = (UIView *)self;
    SGRSingControl *ctrl = objc_getAssociatedObject(host, &kSingControlKey);
    if (!SGSingEnabled()) {
        ctrl.hidden = YES;
        return;
    }
    if (!ctrl) {
        ctrl = [[SGRSingControl alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, &kSingControlKey, ctrl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:ctrl];
    }
    [host bringSubviewToFront:ctrl];
    [ctrl refreshState];
    CGSize sz = [ctrl preferredSize];
    ctrl.frame = CGRectMake(host.bounds.size.width - sz.width - 14, host.bounds.size.height - sz.height - 14, sz.width, sz.height);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
