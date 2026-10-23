// 1:1 Chroma 0.51.0 AirPods Head Gestures: gravity-projected CMHeadphoneMotionManager detector,
// SGHeadTryLine, SGHeadTrySheet, SGHeadRing (60-tick dial), SGHeadTrainSheet (5 nods, 5 shakes, 20s look-around),
// and SGHeadGesturesSettingsPage — 100% unlocked without any Plus pass check.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Gestures.h"
#import <CoreMotion/CoreMotion.h>
#import <AudioToolbox/AudioToolbox.h>

static NSString *const SGKeyHeadLearnedNod   = @"spotifyglass.headGestures.learned.nod";
static NSString *const SGKeyHeadLearnedShake = @"spotifyglass.headGestures.learned.shake";

static BOOL SGHeadHasLearnedCalibration(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:SGKeyHeadLearnedNod] != nil &&
           [NSUserDefaults.standardUserDefaults objectForKey:SGKeyHeadLearnedShake] != nil;
}

static void SGHeadResetLearnedCalibration(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyHeadLearnedNod];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyHeadLearnedShake];
}

#pragma mark - SGHeadGestureWatcher (1:1 Chroma 0.51.0 Motion Engine)

typedef void (^SGHeadTryPoseBlock)(BOOL connected, double yaw, double pitch);
typedef void (^SGHeadTryEventBlock)(BOOL isNod, BOOL counted, NSString *hint, double peakVelocity);

@interface SGHeadGestureWatcher : NSObject <CMHeadphoneMotionManagerDelegate>
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, copy) SGHeadTryPoseBlock poseHandler;
@property (nonatomic, copy) SGHeadTryEventBlock eventHandler;
+ (instancetype)shared;
- (void)refreshState;
@end

@implementation SGHeadGestureWatcher {
    CMHeadphoneMotionManager *_motion;
    NSOperationQueue *_queue;
    BOOL _connected;

    // Relative attitude anchor for smooth UI dot tracking
    double _anchorYaw;
    double _anchorPitch;
    BOOL _hasAnchor;

    // Alternating extrema buffers for Nod (pitch) and Shake (yaw)
    double _nodLastPeakTime;
    double _nodMaxAbs;
    double _nodCrossMax;
    int _nodLastSign;
    int _nodTurnCount;

    double _shakeLastPeakTime;
    double _shakeMaxAbs;
    double _shakeCrossMax;
    int _shakeLastSign;
    int _shakeTurnCount;

    double _cooldownUntil;
    double _lastHintTime;
}

+ (instancetype)shared {
    static SGHeadGestureWatcher *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [SGHeadGestureWatcher new];
    });
    return inst;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    if (@available(iOS 14.0, *)) {
        _motion = [CMHeadphoneMotionManager new];
        _motion.delegate = self;
        _queue = [NSOperationQueue new];
        _queue.name = @"com.spotifyglass.headgestures";
        _queue.maxConcurrentOperationCount = 1;
    }
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshState)
                                               name:NSUserDefaultsDidChangeNotification
                                             object:nil];
    return self;
}

- (BOOL)available {
    if (@available(iOS 14.0, *)) {
        return _motion && _motion.isDeviceMotionAvailable;
    }
    return NO;
}

- (BOOL)connected {
    return _connected;
}

- (void)refreshState {
    if (!self.available) return;
    BOOL shouldRun = SGFlag(SGKeyHeadGestures, NO) || self.poseHandler != nil || self.eventHandler != nil;
    if (shouldRun && !_motion.isDeviceMotionActive) {
        _hasAnchor = NO;
        __weak typeof(self) weakSelf = self;
        [_motion startDeviceMotionUpdatesToQueue:_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
            if (motion && !error) [weakSelf processMotion:motion];
        }];
    } else if (!shouldRun && _motion.isDeviceMotionActive) {
        [_motion stopDeviceMotionUpdates];
        _connected = NO;
        _hasAnchor = NO;
    }
}

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    _connected = YES;
    _hasAnchor = NO;
    if (self.poseHandler) {
        SGHeadTryPoseBlock ph = self.poseHandler;
        dispatch_async(dispatch_get_main_queue(), ^{ ph(YES, 0, 0); });
    }
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    _connected = NO;
    _hasAnchor = NO;
    if (self.poseHandler) {
        SGHeadTryPoseBlock ph = self.poseHandler;
        dispatch_async(dispatch_get_main_queue(), ^{ ph(NO, 0, 0); });
    }
}

- (double)nodThreshold {
    NSNumber *learned = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyHeadLearnedNod];
    if (learned) return fmax(0.95, fmin(3.2, learned.doubleValue));
    NSInteger sens = SGInt(SGKeyHeadGestureSensitivity, 1); // 0=Gentle, 1=Normal, 2=Firm
    return (sens == 0) ? 1.35 : ((sens == 2) ? 2.25 : 1.75);
}

- (double)shakeThreshold {
    NSNumber *learned = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyHeadLearnedShake];
    if (learned) return fmax(0.95, fmin(3.2, learned.doubleValue));
    NSInteger sens = SGInt(SGKeyHeadGestureSensitivity, 1);
    return (sens == 0) ? 1.45 : ((sens == 2) ? 2.40 : 1.85);
}

- (void)processMotion:(CMDeviceMotion *)motion {
    _connected = YES;
    double now = CACurrentMediaTime();

    // 1. Attitude tracking for live UI dot in SGHeadTrySheet and SGHeadRing
    CMAttitude *att = motion.attitude;
    if (!_hasAnchor) {
        _anchorYaw = att.yaw;
        _anchorPitch = att.pitch;
        _hasAnchor = YES;
    }
    double dYaw = att.yaw - _anchorYaw;
    while (dYaw > M_PI) dYaw -= 2.0 * M_PI;
    while (dYaw < -M_PI) dYaw += 2.0 * M_PI;
    double dPitch = att.pitch - _anchorPitch;
    // Soft drift recentering toward neutral pose
    _anchorYaw += dYaw * 0.025;
    _anchorPitch += dPitch * 0.025;

    if (self.poseHandler) {
        SGHeadTryPoseBlock ph = self.poseHandler;
        dispatch_async(dispatch_get_main_queue(), ^{
            ph(YES, dYaw, dPitch);
        });
    }

    if (now < _cooldownUntil) return;

    // 2. Gravity-projected rotation rates (exact Chroma 0.51.0 projection)
    CMRotationRate r = motion.rotationRate;
    CMAcceleration g = motion.gravity;
    double pitchVel = r.x;
    double yawVel = -(r.y * g.y + r.z * g.z);
    if (fabs(r.z) > fabs(yawVel)) yawVel = r.z;

    double nodThresh = [self nodThreshold];
    double shakeThresh = [self shakeThreshold];

    // Check expired partial nod window to emit diagnostic hint in Try sheet
    if (_nodTurnCount > 0 && (now - _nodLastPeakTime) > 0.72) {
        if (self.eventHandler && (now - _lastHintTime) > 1.2) {
            NSString *hint = nil;
            if (_nodCrossMax > _nodMaxAbs * 0.85) {
                hint = @"nod straight up and down";
            } else if (_nodMaxAbs < nodThresh) {
                hint = @"nod a bit firmer";
            } else if (_nodTurnCount < 3) {
                hint = @"nod twice in a row";
            }
            if (hint) {
                _lastHintTime = now;
                SGHeadTryEventBlock eh = self.eventHandler;
                dispatch_async(dispatch_get_main_queue(), ^{ eh(YES, NO, hint, 0); });
            }
        }
        _nodTurnCount = 0;
        _nodLastSign = 0;
        _nodMaxAbs = 0;
        _nodCrossMax = 0;
    }

    // Check expired partial shake window to emit diagnostic hint in Try sheet
    if (_shakeTurnCount > 0 && (now - _shakeLastPeakTime) > 0.72) {
        if (self.eventHandler && (now - _lastHintTime) > 1.2) {
            NSString *hint = nil;
            if (_shakeCrossMax > _shakeMaxAbs * 0.85) {
                hint = @"keep your head level";
            } else if (_shakeMaxAbs < shakeThresh) {
                hint = @"turn a bit faster";
            } else if (_shakeTurnCount < 3) {
                hint = @"shake left and right";
            }
            if (hint) {
                _lastHintTime = now;
                SGHeadTryEventBlock eh = self.eventHandler;
                dispatch_async(dispatch_get_main_queue(), ^{ eh(NO, NO, hint, 0); });
            }
        }
        _shakeTurnCount = 0;
        _shakeLastSign = 0;
        _shakeMaxAbs = 0;
        _shakeCrossMax = 0;
    }

    // Detect Nod extrema
    double partialNodGate = nodThresh * 0.65;
    int pitchSign = (pitchVel > partialNodGate) ? 1 : ((pitchVel < -partialNodGate) ? -1 : 0);
    if (pitchSign != 0) {
        if (fabs(pitchVel) > _nodMaxAbs) _nodMaxAbs = fabs(pitchVel);
        if (fabs(yawVel) > _nodCrossMax) _nodCrossMax = fabs(yawVel);

        if (_nodTurnCount == 0) {
            _nodTurnCount = 1;
            _nodLastSign = pitchSign;
            _nodLastPeakTime = now;
        } else if (pitchSign != _nodLastSign && (now - _nodLastPeakTime) >= 0.07) {
            _nodTurnCount++;
            _nodLastSign = pitchSign;
            _nodLastPeakTime = now;

            if (_nodTurnCount >= 3 && _nodMaxAbs >= nodThresh && _nodMaxAbs > _nodCrossMax * 1.18) {
                double peak = _nodMaxAbs;
                _nodTurnCount = 0;
                _nodMaxAbs = 0;
                _nodCrossMax = 0;
                _shakeTurnCount = 0;
                _cooldownUntil = now + 1.10;
                [self fireRecognizedGestureIsNod:YES peakVelocity:peak];
                return;
            }
        }
    }

    // Detect Shake extrema
    double partialShakeGate = shakeThresh * 0.65;
    int yawSign = (yawVel > partialShakeGate) ? 1 : ((yawVel < -partialShakeGate) ? -1 : 0);
    if (yawSign != 0) {
        if (fabs(yawVel) > _shakeMaxAbs) _shakeMaxAbs = fabs(yawVel);
        if (fabs(pitchVel) > _shakeCrossMax) _shakeCrossMax = fabs(pitchVel);

        if (_shakeTurnCount == 0) {
            _shakeTurnCount = 1;
            _shakeLastSign = yawSign;
            _shakeLastPeakTime = now;
        } else if (yawSign != _shakeLastSign && (now - _shakeLastPeakTime) >= 0.07) {
            _shakeTurnCount++;
            _shakeLastSign = yawSign;
            _shakeLastPeakTime = now;

            if (_shakeTurnCount >= 3 && _shakeMaxAbs >= shakeThresh && _shakeMaxAbs > _shakeCrossMax * 1.18) {
                double peak = _shakeMaxAbs;
                _shakeTurnCount = 0;
                _shakeMaxAbs = 0;
                _shakeCrossMax = 0;
                _nodTurnCount = 0;
                _cooldownUntil = now + 1.10;
                [self fireRecognizedGestureIsNod:NO peakVelocity:peak];
                return;
            }
        }
    }
}

- (void)fireRecognizedGestureIsNod:(BOOL)isNod peakVelocity:(double)peak {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (SGFlag(SGKeyHeadGestureChime, YES)) {
            AudioServicesPlaySystemSound(isNod ? 1057 : 1104);
        }
        UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
        [gen notificationOccurred:UINotificationFeedbackTypeSuccess];

        if (self.eventHandler) {
            self.eventHandler(isNod, YES, nil, peak);
            return;
        }
        if (!SGFlag(SGKeyHeadGestures, NO)) return;
        SGGestureAction action = (SGGestureAction)SGInt(isNod ? SGKeyHeadGestureNod : SGKeyHeadGestureShake,
                                                       isNod ? SGGesturePlayPause : SGGestureNextTrack);
        SGGesturePerformAction(action);
    });
}

@end

#pragma mark - SGHeadTryLine (1:1 Chroma 0.51.0 Row View inside Try Sheet)

@interface SGHeadTryLine : UIView
- (instancetype)initWithSymbol:(NSString *)symbol name:(NSString *)name;
- (void)markDone;
- (void)showHint:(NSString *)hint;
@end

@implementation SGHeadTryLine {
    UIImageView *_icon;
    UILabel *_name;
    UILabel *_note;
    UIImageView *_check;
    int _resetToken;
}

- (instancetype)initWithSymbol:(NSString *)symbol name:(NSString *)name {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;

    UIImageSymbolConfiguration *iconCfg = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:iconCfg]];
    _icon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];

    _name = [UILabel new];
    _name.text = name;
    _name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _name.textColor = UIColor.whiteColor;
    [self addSubview:_name];

    _note = [UILabel new];
    _note.text = @"Not yet";
    _note.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _note.textColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    _note.textAlignment = NSTextAlignmentRight;
    [self addSubview:_note];

    UIImageSymbolConfiguration *chkCfg = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    _check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:chkCfg]];
    _check.tintColor = SGGreen();
    _check.alpha = 0.0;
    [self addSubview:_check];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    _icon.frame = CGRectMake(16.0, (h - 22.0) * 0.5, 22.0, 22.0);
    _name.frame = CGRectMake(48.0, 0, 120.0, h);
    CGFloat rightEdge = (_check.alpha > 0.01) ? (w - 42.0) : (w - 16.0);
    _note.frame = CGRectMake(156.0, 0, rightEdge - 156.0, h);
    _check.frame = CGRectMake(w - 34.0, (h - 20.0) * 0.5, 20.0, 20.0);
}

- (void)markDone {
    int token = ++_resetToken;
    _note.text = @"Counted";
    _note.textColor = SGGreen();
    _icon.tintColor = SGGreen();
    _check.transform = CGAffineTransformMakeScale(0.5, 0.5);
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:0 options:0 animations:^{
        self->_check.alpha = 1.0;
        self->_check.transform = CGAffineTransformIdentity;
        [self layoutSubviews];
    } completion:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_resetToken != token) return;
        [UIView animateWithDuration:0.25 animations:^{
            self->_icon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        }];
    });
}

- (void)showHint:(NSString *)hint {
    if (!hint.length) return;
    int token = ++_resetToken;
    _note.text = [NSString stringWithFormat:@"Almost · %@", hint];
    _note.textColor = [UIColor colorWithWhite:1.0 alpha:0.58];
    [UIView animateWithDuration:0.2 animations:^{
        self->_check.alpha = 0.0;
        [self layoutSubviews];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_resetToken != token) return;
        self->_note.text = @"Not yet";
        self->_note.textColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    });
}

@end

#pragma mark - SGHeadTrySheet (1:1 Chroma 0.51.0 "Try AirPods gestures" Sheet)

@interface SGHeadTrySheet : UIViewController
@end

@implementation SGHeadTrySheet {
    UILabel *_titleLabel;
    UIButton *_doneBtn;
    UIView *_pad;
    UIView *_crossH;
    UIView *_crossV;
    UIView *_dot;
    UILabel *_status;
    UIView *_card;
    SGHeadTryLine *_nod;
    UIView *_divider;
    SGHeadTryLine *_shake;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SGCardSurfaceColor();

    _titleLabel = [UILabel new];
    _titleLabel.text = @"Try AirPods gestures";
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_titleLabel];

    _doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    _doneBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_doneBtn setTitleColor:SGGreen() forState:UIControlStateNormal];
    [_doneBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_doneBtn];

    _pad = [UIView new];
    _pad.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    _pad.layer.cornerRadius = 37.0;
    _pad.layer.borderWidth = 1.0;
    _pad.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
    [self.view addSubview:_pad];

    _crossH = [UIView new];
    _crossH.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [_pad addSubview:_crossH];

    _crossV = [UIView new];
    _crossV.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [_pad addSubview:_crossV];

    _dot = [UIView new];
    _dot.backgroundColor = SGGreen();
    _dot.layer.cornerRadius = 9.0;
    [_pad addSubview:_dot];

    _status = [UILabel new];
    _status.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _status.textColor = [UIColor colorWithWhite:1.0 alpha:0.52];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 2;
    [self.view addSubview:_status];

    _card = [UIView new];
    _card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    _card.layer.cornerRadius = 14.0;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.clipsToBounds = YES;
    [self.view addSubview:_card];

    _nod = [[SGHeadTryLine alloc] initWithSymbol:@"arrow.up.and.down" name:@"Nod twice"];
    [_card addSubview:_nod];

    _divider = [UIView new];
    _divider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [_card addSubview:_divider];

    _shake = [[SGHeadTryLine alloc] initWithSymbol:@"arrow.left.and.right" name:@"Shake head"];
    [_card addSubview:_shake];

    [self updateStatusConnected:SGHeadGestureWatcher.shared.connected];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    _titleLabel.frame = CGRectMake(60.0, 20.0, w - 120.0, 22.0);
    _doneBtn.frame = CGRectMake(w - 72.0, 15.0, 56.0, 32.0);

    _pad.frame = CGRectMake((w - 74.0) * 0.5, 62.0, 74.0, 74.0);
    _crossH.frame = CGRectMake(12.0, 36.5, 50.0, 1.0);
    _crossV.frame = CGRectMake(36.5, 12.0, 1.0, 50.0);
    if (CGRectIsEmpty(_dot.frame)) {
        _dot.frame = CGRectMake(28.0, 28.0, 18.0, 18.0);
    }

    _status.frame = CGRectMake(24.0, 148.0, w - 48.0, 34.0);
    _card.frame = CGRectMake(20.0, 196.0, w - 40.0, 108.0);
    CGFloat cw = _card.bounds.size.width;
    _nod.frame = CGRectMake(0, 0, cw, 54.0);
    _divider.frame = CGRectMake(48.0, 53.5, cw - 48.0, 0.5);
    _shake.frame = CGRectMake(0, 54.0, cw, 54.0);
}

- (void)updateStatusConnected:(BOOL)connected {
    if (!SGHeadGestureWatcher.shared.available) {
        _status.text = @"Needs AirPods Pro, AirPods Max, AirPods 3 or 4, or Beats with head tracking";
        _dot.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    } else if (connected) {
        _status.text = @"Nod twice or shake your head";
        _dot.backgroundColor = SGGreen();
    } else {
        _status.text = @"Put in your AirPods and play something";
        _dot.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak typeof(self) weakSelf = self;
    SGHeadGestureWatcher.shared.poseHandler = ^(BOOL connected, double yaw, double pitch) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateStatusConnected:connected];
        CGFloat tx = (CGFloat)fmax(-21.0, fmin(21.0, -yaw * 36.0));
        CGFloat ty = (CGFloat)fmax(-21.0, fmin(21.0, -pitch * 36.0));
        strongSelf->_dot.center = CGPointMake(37.0 + tx, 37.0 + ty);
    };
    SGHeadGestureWatcher.shared.eventHandler = ^(BOOL isNod, BOOL counted, NSString *hint, double peakVel) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        SGHeadTryLine *line = isNod ? strongSelf->_nod : strongSelf->_shake;
        if (counted) {
            [line markDone];
            [UIView animateWithDuration:0.15 animations:^{
                strongSelf->_dot.transform = CGAffineTransformMakeScale(1.38, 1.38);
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.22 animations:^{
                    strongSelf->_dot.transform = CGAffineTransformIdentity;
                }];
            }];
        } else if (hint) {
            [line showHint:hint];
        }
    };
    [SGHeadGestureWatcher.shared refreshState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    SGHeadGestureWatcher.shared.poseHandler = nil;
    SGHeadGestureWatcher.shared.eventHandler = nil;
    [SGHeadGestureWatcher.shared refreshState];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - SGHeadRing (1:1 Chroma 0.51.0 60-Tick Calibration Dial)

@interface SGHeadRing : UIView
- (void)setLitTicks:(NSInteger)lit pulse:(BOOL)pulse;
- (void)setComplete:(BOOL)complete;
- (void)setHeadOffset:(CGPoint)offset connected:(BOOL)connected;
- (void)flashDot;
@end

@implementation SGHeadRing {
    NSArray<CAShapeLayer *> *_ticks;
    UIView *_centerCrossH;
    UIView *_centerCrossV;
    UIView *_dot;
    NSInteger _litCount;
    BOOL _complete;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NSMutableArray<CAShapeLayer *> *arr = [NSMutableArray arrayWithCapacity:60];
    for (int i = 0; i < 60; i++) {
        CAShapeLayer *t = [CAShapeLayer layer];
        t.lineWidth = 2.5;
        t.lineCap = kCALineCapRound;
        t.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
        [self.layer addSublayer:t];
        [arr addObject:t];
    }
    _ticks = [arr copy];

    _centerCrossH = [UIView new];
    _centerCrossH.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    [self addSubview:_centerCrossH];

    _centerCrossV = [UIView new];
    _centerCrossV.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    [self addSubview:_centerCrossV];

    _dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18.0, 18.0)];
    _dot.backgroundColor = SGGreen();
    _dot.layer.cornerRadius = 9.0;
    [self addSubview:_dot];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGPoint c = CGPointMake(w * 0.5, h * 0.5);
    CGFloat outerR = MIN(w, h) * 0.5 - 8.0;
    CGFloat innerR = outerR - 12.0;

    for (int i = 0; i < 60; i++) {
        double a = ((double)i / 60.0) * 2.0 * M_PI - M_PI_2;
        CGPoint p1 = CGPointMake(c.x + cos(a) * innerR, c.y + sin(a) * innerR);
        CGPoint p2 = CGPointMake(c.x + cos(a) * outerR, c.y + sin(a) * outerR);
        UIBezierPath *bp = [UIBezierPath bezierPath];
        [bp moveToPoint:p1];
        [bp addLineToPoint:p2];
        _ticks[(NSUInteger)i].path = bp.CGPath;
    }

    _centerCrossH.frame = CGRectMake(c.x - 28.0, c.y - 0.5, 56.0, 1.0);
    _centerCrossV.frame = CGRectMake(c.x - 0.5, c.y - 28.0, 1.0, 56.0);
    if (CGPointEqualToPoint(_dot.center, CGPointZero)) {
        _dot.center = c;
    }
}

- (void)setLitTicks:(NSInteger)lit pulse:(BOOL)pulse {
    _litCount = MAX(0, MIN(60, lit));
    for (int i = 0; i < 60; i++) {
        BOOL on = _complete || (i < _litCount);
        _ticks[(NSUInteger)i].strokeColor = on ? SGGreen().CGColor : [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    }
    if (pulse) {
        [UIView animateWithDuration:0.14 animations:^{
            self.transform = CGAffineTransformMakeScale(1.03, 1.03);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.20 animations:^{
                self.transform = CGAffineTransformIdentity;
            }];
        }];
    }
}

- (void)setComplete:(BOOL)complete {
    _complete = complete;
    [self setLitTicks:complete ? 60 : _litCount pulse:complete];
}

- (void)setHeadOffset:(CGPoint)offset connected:(BOOL)connected {
    CGPoint c = CGPointMake(self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
    _dot.backgroundColor = connected ? SGGreen() : [UIColor colorWithWhite:1.0 alpha:0.28];
    _dot.center = CGPointMake(c.x + offset.x, c.y + offset.y);
}

- (void)flashDot {
    [UIView animateWithDuration:0.14 animations:^{
        self->_dot.transform = CGAffineTransformMakeScale(1.45, 1.45);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.22 animations:^{
            self->_dot.transform = CGAffineTransformIdentity;
        }];
    }];
}

@end

#pragma mark - SGHeadTrainSheet (1:1 Chroma 0.51.0 "Learn how you nod and shake" Sheet)

@interface SGHeadTrainSheet : UIViewController
@property (nonatomic, copy) void (^finishedCalibration)(void);
@end

@implementation SGHeadTrainSheet {
    UIButton *_cancelBtn;
    SGHeadRing *_ring;
    UILabel *_title;
    UILabel *_sub;
    UILabel *_counter;
    UIButton *_primaryBtn;

    NSInteger _stage; // 0=Intro, 1=5 Nods, 2=5 Shakes, 3=20s Normal, 4=Done
    NSInteger _nodSamplesCount;
    double _nodPeakSum;
    NSInteger _shakeSamplesCount;
    double _shakePeakSum;
    NSTimer *_lookTimer;
    int _lookSecondsRemaining;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SGCardSurfaceColor();

    _cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelBtn setTitle:@"Cancel" forState:UIControlStateNormal];
    _cancelBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    [_cancelBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.65] forState:UIControlStateNormal];
    [_cancelBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelBtn];

    _ring = [[SGHeadRing alloc] initWithFrame:CGRectMake(0, 0, 240, 240)];
    [self.view addSubview:_ring];

    _counter = [UILabel new];
    _counter.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    _counter.textColor = SGGreen();
    _counter.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_counter];

    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    _title.textColor = UIColor.whiteColor;
    _title.textAlignment = NSTextAlignmentCenter;
    _title.numberOfLines = 2;
    [self.view addSubview:_title];

    _sub = [UILabel new];
    _sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.58];
    _sub.textAlignment = NSTextAlignmentCenter;
    _sub.numberOfLines = 3;
    [self.view addSubview:_sub];

    _primaryBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _primaryBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_primaryBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    _primaryBtn.backgroundColor = SGGreen();
    _primaryBtn.layer.cornerRadius = 24.0;
    _primaryBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [_primaryBtn addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_primaryBtn];

    [self enterStage:0];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    _cancelBtn.frame = CGRectMake(16.0, 16.0, 70.0, 32.0);
    _ring.frame = CGRectMake((w - 230.0) * 0.5, 54.0, 230.0, 230.0);
    _counter.frame = CGRectMake(24.0, 296.0, w - 48.0, 18.0);
    _title.frame = CGRectMake(24.0, 318.0, w - 48.0, 32.0);
    _sub.frame = CGRectMake(28.0, 354.0, w - 56.0, 62.0);
    _primaryBtn.frame = CGRectMake(24.0, h - self.view.safeAreaInsets.bottom - 66.0, w - 48.0, 48.0);
}

- (void)enterStage:(NSInteger)stage {
    _stage = stage;
    [_lookTimer invalidate];
    _lookTimer = nil;

    if (stage == 0) {
        _counter.text = @"CALIBRATION";
        _title.text = @"Learn how you nod and shake";
        _sub.text = @"Do 5 nods and 5 shakes the way that feels natural to you, then move your head normally for a few seconds.";
        [_primaryBtn setTitle:@"Start" forState:UIControlStateNormal];
        _primaryBtn.hidden = NO;
        [_ring setComplete:NO];
        [_ring setLitTicks:0 pulse:NO];
    } else if (stage == 1) {
        _nodSamplesCount = 0;
        _nodPeakSum = 0;
        _counter.text = @"1 OF 5";
        _title.text = @"Nod twice";
        _sub.text = @"Give two natural nods down and up, the way you'd do it while listening.";
        _primaryBtn.hidden = YES;
        [_ring setLitTicks:0 pulse:NO];
    } else if (stage == 2) {
        _shakeSamplesCount = 0;
        _shakePeakSum = 0;
        _counter.text = @"1 OF 5";
        _title.text = @"Shake your head";
        _sub.text = @"Turn your head left and right naturally.";
        _primaryBtn.hidden = YES;
        [_ring setLitTicks:0 pulse:NO];
    } else if (stage == 3) {
        _lookSecondsRemaining = 10;
        _counter.text = @"10S LEFT";
        _title.text = @"Look around normally";
        _sub.text = @"Glance around the room so casual head turns aren't mistaken for gestures.";
        _primaryBtn.hidden = YES;
        [_ring setLitTicks:0 pulse:NO];
        _lookTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tickLookAround) userInfo:nil repeats:YES];
    } else if (stage == 4) {
        double learnedNod = (_nodSamplesCount > 0) ? fmax(1.05, (_nodPeakSum / _nodSamplesCount) * 0.78) : 1.65;
        double learnedShake = (_shakeSamplesCount > 0) ? fmax(1.10, (_shakePeakSum / _shakeSamplesCount) * 0.78) : 1.75;
        [NSUserDefaults.standardUserDefaults setDouble:learnedNod forKey:SGKeyHeadLearnedNod];
        [NSUserDefaults.standardUserDefaults setDouble:learnedShake forKey:SGKeyHeadLearnedShake];
        if (self.finishedCalibration) self.finishedCalibration();

        _counter.text = @"COMPLETE";
        _title.text = @"Tuned to you";
        _sub.text = @"Your nod and shake thresholds have been saved on this iPhone.";
        [_primaryBtn setTitle:@"Done" forState:UIControlStateNormal];
        _primaryBtn.hidden = NO;
        [_ring setComplete:YES];
    }
}

- (void)tickLookAround {
    _lookSecondsRemaining--;
    NSInteger lit = ((10 - _lookSecondsRemaining) * 60) / 10;
    [_ring setLitTicks:lit pulse:NO];
    if (_lookSecondsRemaining <= 0) {
        [_lookTimer invalidate];
        _lookTimer = nil;
        [self enterStage:4];
    } else {
        _counter.text = [NSString stringWithFormat:@"%dS LEFT", _lookSecondsRemaining];
    }
}

- (void)primaryTapped {
    if (_stage == 0) {
        [self enterStage:1];
    } else {
        [self close];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak typeof(self) weakSelf = self;
    SGHeadGestureWatcher.shared.poseHandler = ^(BOOL connected, double yaw, double pitch) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        CGFloat tx = (CGFloat)fmax(-46.0, fmin(46.0, -yaw * 72.0));
        CGFloat ty = (CGFloat)fmax(-46.0, fmin(46.0, -pitch * 72.0));
        [strongSelf->_ring setHeadOffset:CGPointMake(tx, ty) connected:connected];
    };
    SGHeadGestureWatcher.shared.eventHandler = ^(BOOL isNod, BOOL counted, NSString *hint, double peakVel) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !counted) return;
        if (strongSelf->_stage == 1 && isNod) {
            strongSelf->_nodSamplesCount++;
            strongSelf->_nodPeakSum += (peakVel > 0 ? peakVel : 1.75);
            [strongSelf->_ring flashDot];
            [strongSelf->_ring setLitTicks:strongSelf->_nodSamplesCount * 12 pulse:YES];
            if (strongSelf->_nodSamplesCount >= 5) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [strongSelf enterStage:2];
                });
            } else {
                strongSelf->_counter.text = [NSString stringWithFormat:@"%ld OF 5", (long)(strongSelf->_nodSamplesCount + 1)];
            }
        } else if (strongSelf->_stage == 2 && !isNod) {
            strongSelf->_shakeSamplesCount++;
            strongSelf->_shakePeakSum += (peakVel > 0 ? peakVel : 1.85);
            [strongSelf->_ring flashDot];
            [strongSelf->_ring setLitTicks:strongSelf->_shakeSamplesCount * 12 pulse:YES];
            if (strongSelf->_shakeSamplesCount >= 5) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [strongSelf enterStage:3];
                });
            } else {
                strongSelf->_counter.text = [NSString stringWithFormat:@"%ld OF 5", (long)(strongSelf->_shakeSamplesCount + 1)];
            }
        }
    };
    [SGHeadGestureWatcher.shared refreshState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_lookTimer invalidate];
    _lookTimer = nil;
    SGHeadGestureWatcher.shared.poseHandler = nil;
    SGHeadGestureWatcher.shared.eventHandler = nil;
    [SGHeadGestureWatcher.shared refreshState];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Settings Page (1:1 Chroma 0.51.0 Layout)

NSString *SGHeadGesturesSummary(void) {
    return SGFlag(SGKeyHeadGestures, NO) ? @"On" : @"Off";
}

UIViewController *SGHeadGesturesSettingsPage(void) {
    __weak __block SGModPage *weakPage = nil;
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"AirPods gestures" build:^NSArray<SGModSection *> *{
        SGModRow *enableRow = SGWithSymbol(SGSwitchRow(@"AirPods gestures", @"Nod or shake your head to control playback", SGKeyHeadGestures), @"airpodspro");
        enableRow.glows = YES;
        enableRow.changed = ^(BOOL on) {
            [SGHeadGestureWatcher.shared refreshState];
        };

        SGModRow *nodRow = SGWithSymbol(SGChoiceRow(@"Nod twice", nil, SGKeyHeadGestureNod, SGGestureActionNames(), SGGesturePlayPause), @"arrow.up.and.down");
        SGModRow *shakeRow = SGWithSymbol(SGChoiceRow(@"Shake head", nil, SGKeyHeadGestureShake, SGGestureActionNames(), SGGestureNextTrack), @"arrow.left.and.right");

        SGModRow *sensRow = SGWithSymbol(SGChoiceRow(@"Sensitivity", nil, SGKeyHeadGestureSensitivity, @[@"Gentle", @"Normal", @"Firm"], 1), @"dial.medium");
        sensRow.choiceNotes = @[
            @"Picks up smaller, lighter nods and shakes",
            @"Balanced for everyday listening",
            @"Needs a clearer, more deliberate nod or shake"
        ];

        SGModRow *chimeRow = SGWithSymbol(SGSwitchRow(@"Confirmation sound", @"A soft tone in your AirPods when a gesture is recognized", SGKeyHeadGestureChime), @"speaker.wave.2");

        SGModRow *tryRow = SGWithSymbol(SGActionRow(@"Try gestures", @"Test your nods and shakes live", ^{
            SGHeadTrySheet *sheet = [SGHeadTrySheet new];
            if (@available(iOS 16.0, *)) {
                sheet.modalPresentationStyle = UIModalPresentationPageSheet;
                UISheetPresentationController *sp = sheet.sheetPresentationController;
                sp.prefersGrabberVisible = YES;
                sp.preferredCornerRadius = 28.0;
                sp.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"try" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) {
                    return 340.0;
                }]];
            } else if (@available(iOS 15.0, *)) {
                sheet.modalPresentationStyle = UIModalPresentationPageSheet;
                sheet.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
            }
            [weakPage presentViewController:sheet animated:YES completion:nil];
        }), @"hand.wave");

        NSString *learnSub = SGHeadHasLearnedCalibration() ? @"Tuned to you" : @"Calibrate to your movements";
        SGModRow *trainRow = SGWithSymbol(SGActionRow(@"Learn how you nod and shake", learnSub, ^{
            SGHeadTrainSheet *sheet = [SGHeadTrainSheet new];
            sheet.finishedCalibration = ^{ [weakPage rebuild]; };
            if (@available(iOS 16.0, *)) {
                sheet.modalPresentationStyle = UIModalPresentationPageSheet;
                UISheetPresentationController *sp = sheet.sheetPresentationController;
                sp.prefersGrabberVisible = YES;
                sp.preferredCornerRadius = 28.0;
                sp.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"train" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) {
                    return 500.0;
                }]];
            } else if (@available(iOS 15.0, *)) {
                sheet.modalPresentationStyle = UIModalPresentationPageSheet;
                sheet.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
            }
            [weakPage presentViewController:sheet animated:YES completion:nil];
        }), @"waveform.badge.magnifyingglass");

        NSMutableArray<SGModRow *> *responseRows = [NSMutableArray arrayWithObjects:sensRow, chimeRow, tryRow, trainRow, nil];
        if (SGHeadHasLearnedCalibration()) {
            SGModRow *resetRow = SGWithSymbol(SGWarningRow(@"Use default sensitivity", nil, ^{
                SGHeadResetLearnedCalibration();
                [weakPage rebuild];
            }), @"arrow.counterclockwise");
            [responseRows addObject:resetRow];
        }

        return @[
            SGNotedSection(nil, @[enableRow], @"Requires AirPods Pro, AirPods Max, AirPods (3rd generation) or Beats with head tracking. Works while listening to music."),
            SGSection(@"Actions", @[nodRow, shakeRow]),
            SGSection(@"Response", responseRows),
        ];
    }];
    weakPage = page;
    return page;
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [SGHeadGestureWatcher.shared refreshState];
    });
}
