// AirPods Head Gestures: double nod & head shake via CMHeadphoneMotionManager, with live test sheet.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Gestures.h"
#import <CoreMotion/CoreMotion.h>
#import <AudioToolbox/AudioToolbox.h>

@interface SGHeadGestureWatcher : NSObject <CMHeadphoneMotionManagerDelegate>
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, copy) void (^testHandler)(BOOL isNod, double pitchRate, double yawRate);
+ (instancetype)shared;
- (void)refreshState;
@end

@implementation SGHeadGestureWatcher {
    CMHeadphoneMotionManager *_motion;
    NSOperationQueue *_queue;
    double _lastNodSignTime;
    int _nodSignCount;
    int _lastNodSign;
    double _lastShakeSignTime;
    int _shakeSignCount;
    int _lastShakeSign;
    double _cooldownUntil;
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
        _queue.name = @"pw.spoti.headgestures";
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
    if (@available(iOS 14.0, *)) {
        return _motion && _motion.isDeviceMotionActive;
    }
    return NO;
}

- (void)refreshState {
    if (!self.available) return;
    BOOL shouldRun = SGFlag(SGKeyHeadGestures, NO) || self.testHandler != nil;
    if (shouldRun && !_motion.isDeviceMotionActive) {
        __weak typeof(self) weakSelf = self;
        [_motion startDeviceMotionUpdatesToQueue:_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
            if (motion) [weakSelf processMotion:motion];
        }];
    } else if (!shouldRun && _motion.isDeviceMotionActive) {
        [_motion stopDeviceMotionUpdates];
    }
}

- (void)processMotion:(CMDeviceMotion *)motion {
    double now = CACurrentMediaTime();
    CMRotationRate rate = motion.rotationRate;
    double pitchRate = rate.x;
    double yawRate = fabs(rate.z) > fabs(rate.y) ? rate.z : rate.y;

    if (self.testHandler) {
        void (^handler)(BOOL, double, double) = self.testHandler;
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(NO, pitchRate, yawRate);
        });
    }

    if (now < _cooldownUntil) return;

    NSInteger sensIdx = SGInt(SGKeyHeadGestureSensitivity, 1); // 0=Light, 1=Normal, 2=Firm
    double threshold = (sensIdx == 0) ? 1.45 : (sensIdx == 2 ? 2.45 : 1.90);

    int pitchSign = (pitchRate > threshold) ? 1 : ((pitchRate < -threshold) ? -1 : 0);
    if (pitchSign != 0 && fabs(yawRate) < threshold * 0.85) {
        if (now - _lastNodSignTime > 0.68) {
            _nodSignCount = 1;
            _lastNodSign = pitchSign;
            _lastNodSignTime = now;
        } else if (pitchSign != _lastNodSign) {
            _nodSignCount++;
            _lastNodSign = pitchSign;
            _lastNodSignTime = now;
            if (_nodSignCount >= 3) {
                _nodSignCount = 0;
                _cooldownUntil = now + 1.15;
                [self triggerGestureIsNod:YES];
                return;
            }
        }
    }

    int yawSign = (yawRate > threshold) ? 1 : ((yawRate < -threshold) ? -1 : 0);
    if (yawSign != 0 && fabs(pitchRate) < threshold * 0.85) {
        if (now - _lastShakeSignTime > 0.68) {
            _shakeSignCount = 1;
            _lastShakeSign = yawSign;
            _lastShakeSignTime = now;
        } else if (yawSign != _lastShakeSign) {
            _shakeSignCount++;
            _lastShakeSign = yawSign;
            _lastShakeSignTime = now;
            if (_shakeSignCount >= 3) {
                _shakeSignCount = 0;
                _cooldownUntil = now + 1.15;
                [self triggerGestureIsNod:NO];
                return;
            }
        }
    }
}

- (void)triggerGestureIsNod:(BOOL)isNod {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (SGFlag(SGKeyHeadGestureChime, YES)) {
            AudioServicesPlaySystemSound(isNod ? 1057 : 1104);
        }
        UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
        [gen notificationOccurred:UINotificationFeedbackTypeSuccess];

        if (self.testHandler) {
            self.testHandler(isNod, isNod ? 999.0 : 0.0, isNod ? 0.0 : 999.0);
            return;
        }
        if (!SGFlag(SGKeyHeadGestures, NO)) return;
        SGGestureAction action = (SGGestureAction)SGInt(isNod ? SGKeyHeadGestureNod : SGKeyHeadGestureShake,
                                                       isNod ? SGGestureNextTrack : SGGesturePreviousTrack);
        SGGesturePerformAction(action);
    });
}

@end

#pragma mark - Interactive Try Sheet

@interface SGHeadTrySheet : UIViewController
@end

@implementation SGHeadTrySheet {
    UIImageView *_headIcon;
    UILabel *_statusLabel;
    UILabel *_detailLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];

    UILabel *title = [UILabel new];
    title.text = @"Try AirPods Gestures";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    _statusLabel = [UILabel new];
    _statusLabel.text = @"Move your head to test";
    _statusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _statusLabel.textColor = SGGreen();
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    _detailLabel = [UILabel new];
    _detailLabel.text = @"Give two quick nods down, or a quick left-right shake with compatible AirPods.";
    _detailLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _detailLabel.textColor = [UIColor colorWithWhite:1 alpha:0.62];
    _detailLabel.textAlignment = NSTextAlignmentCenter;
    _detailLabel.numberOfLines = 0;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_detailLabel];

    UIView *stage = [UIView new];
    stage.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
    stage.layer.cornerRadius = 24;
    stage.layer.cornerCurve = kCACornerCurveContinuous;
    stage.layer.borderWidth = 1;
    stage.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    stage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stage];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightMedium];
    _headIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"airpodspro" withConfiguration:cfg]];
    _headIcon.tintColor = UIColor.whiteColor;
    _headIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [stage addSubview:_headIcon];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [doneBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    doneBtn.backgroundColor = SGGreen();
    doneBtn.layer.cornerRadius = 14;
    doneBtn.layer.cornerCurve = kCACornerCurveContinuous;
    doneBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [doneBtn addTarget:self action:@selector(closeSheet) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:doneBtn];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:26],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [_statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_detailLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
        [stage.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:22],
        [stage.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stage.widthAnchor constraintEqualToConstant:160],
        [stage.heightAnchor constraintEqualToConstant:160],
        [_headIcon.centerXAnchor constraintEqualToAnchor:stage.centerXAnchor],
        [_headIcon.centerYAnchor constraintEqualToAnchor:stage.centerYAnchor],
        [doneBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [doneBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [doneBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [doneBtn.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    __weak typeof(self) weakSelf = self;
    SGHeadGestureWatcher.shared.testHandler = ^(BOOL isNod, double pitchRate, double yawRate) {
        [weakSelf handleTestUpdateIsNod:isNod pitchRate:pitchRate yawRate:yawRate];
    };
    [SGHeadGestureWatcher.shared refreshState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    SGHeadGestureWatcher.shared.testHandler = nil;
    [SGHeadGestureWatcher.shared refreshState];
}

- (void)handleTestUpdateIsNod:(BOOL)isNod pitchRate:(double)pitchRate yawRate:(double)yawRate {
    if (pitchRate > 500.0 || yawRate > 500.0) {
        _statusLabel.text = isNod ? @"Double nod registered!" : @"Head shake registered!";
        _headIcon.tintColor = SGGreen();
        [UIView animateWithDuration:0.25 animations:^{
            self->_headIcon.transform = CGAffineTransformMakeScale(1.22, 1.22);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.25 animations:^{
                self->_headIcon.transform = CGAffineTransformIdentity;
            }];
        }];
        return;
    }
    CGFloat tx = (CGFloat)fmax(-24.0, fmin(24.0, -yawRate * 10.0));
    CGFloat ty = (CGFloat)fmax(-24.0, fmin(24.0, -pitchRate * 10.0));
    _headIcon.transform = CGAffineTransformMakeTranslation(tx, ty);
}

- (void)closeSheet {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Settings Page

NSString *SGHeadGesturesSummary(void) {
    return SGFlag(SGKeyHeadGestures, NO) ? @"On" : @"Off";
}

UIViewController *SGHeadGesturesSettingsPage(void) {
    __weak __block SGModPage *weakPage = nil;
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"AirPods gestures" build:^NSArray<SGModSection *> *{
        SGModRow *enableRow = SGWithSymbol(SGOptionRow(@"AirPods head gestures", @"Respond to head movements while listening", SGKeyHeadGestures), @"airpodspro");
        enableRow.glows = YES;
        enableRow.changed = ^(BOOL on) {
            [SGHeadGestureWatcher.shared refreshState];
        };

        SGModRow *tryRow = SGWithSymbol(SGActionRow(@"Try gestures…", @"Test double nod and head shake live", ^{
            SGHeadTrySheet *sheet = [SGHeadTrySheet new];
            if (@available(iOS 15.0, *)) {
                sheet.modalPresentationStyle = UIModalPresentationPageSheet;
                sheet.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
            }
            [weakPage presentViewController:sheet animated:YES completion:nil];
        }), @"sparkles");

        SGModRow *nodRow = SGWithSymbol(SGChoiceRow(@"Nod twice", nil, SGKeyHeadGestureNod, SGGestureActionNames(), SGGestureNextTrack), @"arrow.up.and.down");
        SGModRow *shakeRow = SGWithSymbol(SGChoiceRow(@"Shake head", nil, SGKeyHeadGestureShake, SGGestureActionNames(), SGGesturePreviousTrack), @"arrow.left.and.right");

        SGModRow *sensRow = SGWithSymbol(SGChoiceRow(@"Sensitivity", nil, SGKeyHeadGestureSensitivity, @[@"Light", @"Normal", @"Firm"], 1), @"dial.medium");
        SGModRow *chimeRow = SGWithSymbol(SGSwitchRow(@"Confirmation chime", @"Play a subtle tone when a gesture triggers", SGKeyHeadGestureChime), @"bell.fill");

        return @[
            SGNotedSection(nil, @[enableRow, tryRow], @"Control playback hands-free with compatible AirPods (Pro, Max, 3rd gen or newer)."),
            SGSection(@"Actions", @[nodRow, shakeRow]),
            SGSection(@"Feel", @[sensRow, chimeRow]),
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
