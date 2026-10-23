// A double tap on the player, read against the grid Settings draws, plus Hold edge to play faster.
#import "Core/SGCore.h"
#import "Gestures.h"
#import "Shared/Player/SpeedPitch.h"
#import "Headers/SPTNowPlayingPlaybackController.h"

static __weak SPTNowPlayingPlaybackControllerImplementation *sg_player;
static void (^sg_observer)(SGGestureAction action);
static double sg_savedSpeedBeforeHold = 1.0;
static BOOL sg_holdingEdge = NO;

void SGGestureSetObserver(void (^observer)(SGGestureAction action)) {
    sg_observer = [observer copy];
}

#pragma mark - what a cell does

void SGGesturePerformAction(SGGestureAction action) {
    SPTNowPlayingPlaybackControllerImplementation *player = sg_player;
    if (!player) return;
    if (action != SGGestureNothing && sg_observer) sg_observer(action);
    switch (action) {
        case SGGestureNothing:
            break;
        case SGGestureSeekBack:
            if (player.seekingAllowed) [player seekBackwardBySeconds:SGGestureStep()];
            break;
        case SGGestureSeekForward:
            if (player.seekingAllowed) [player seekForwardBySeconds:SGGestureStep()];
            break;
        case SGGesturePlayPause:
            if (player.isPaused ? !player.disallowResuming : !player.disallowPausing) {
                [player setPaused:!player.isPaused];
            }
            break;
        case SGGestureNextTrack:
            if (player.canSkipNext) [player skipToNextWhileDragging:NO];
            break;
        case SGGesturePreviousTrack:
            [player skipToPreviousWhileDragging:NO];
            break;
        case SGGestureShuffle:
            [player setGlobalShuffleMode:!player.isShuffling];
            break;
        case SGGestureRepeat:
            [player toggleRepeatMode];
            break;
    }
}

#pragma mark - the recognizer

@interface SGGestureTarget : NSObject
@end

@implementation SGGestureTarget

- (void)doubleTapped:(UITapGestureRecognizer *)tap {
    if (!SGFlag(SGKeyGestures, NO)) return;
    UIView *host = tap.view;
    CGRect visible = host.bounds;
    CGPoint point = [tap locationInView:host];
    point.x -= visible.origin.x;
    point.y -= visible.origin.y;
    NSInteger cell = SGGestureCellAt(point, visible.size);
    NSArray<NSNumber *> *zones = SGGestureZones();
    if (cell < 0 || cell >= (NSInteger)zones.count) return;
    SGGesturePerformAction((SGGestureAction)zones[(NSUInteger)cell].integerValue);
}

- (void)edgeHeld:(UILongPressGestureRecognizer *)hold {
    if (!SGFlag(SGKeyGestureHold, NO)) return;
    UIView *host = hold.view;
    if (!host) return;
    if (hold.state == UIGestureRecognizerStateBegan) {
        CGRect visible = host.bounds;
        CGPoint point = [hold locationInView:host];
        point.x -= visible.origin.x;
        CGFloat edgeWidth = MAX(48.0, visible.size.width * 0.22);
        if (point.x > edgeWidth && point.x < visible.size.width - edgeWidth) return;
        sg_savedSpeedBeforeHold = SGPlayerSpeed();
        sg_holdingEdge = YES;
        SGSetPlayerSpeed(SGGestureHoldSpeed());
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    } else if (hold.state == UIGestureRecognizerStateEnded ||
               hold.state == UIGestureRecognizerStateCancelled ||
               hold.state == UIGestureRecognizerStateFailed) {
        if (sg_holdingEdge) {
            sg_holdingEdge = NO;
            SGSetPlayerSpeed(sg_savedSpeedBeforeHold);
            UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gen impactOccurred];
        }
    }
}

@end

static SGGestureTarget *target(void) {
    static SGGestureTarget *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGGestureTarget new]; });
    return shared;
}

static void yieldSingleTaps(UIView *host, UITapGestureRecognizer *tap) {
    for (UIView *view = host; view; view = view.superview) {
        for (UIGestureRecognizer *other in view.gestureRecognizers) {
            if (other == tap || ![other isKindOfClass:UITapGestureRecognizer.class]) continue;
            if (((UITapGestureRecognizer *)other).numberOfTapsRequired != 1) continue;
            [other requireGestureRecognizerToFail:tap];
        }
    }
}

static char kTapKey, kHoldKey, kSeenKey;

static NSUInteger tapsAbove(UIView *host) {
    NSUInteger count = 0;
    for (UIView *view = host; view; view = view.superview) count += view.gestureRecognizers.count;
    return count;
}

void SGGestureAttach(UIView *host) {
    if (!host) return;
    if (SGFlag(SGKeyGestureHold, NO)) {
        UILongPressGestureRecognizer *hold = objc_getAssociatedObject(host, &kHoldKey);
        if (!hold) {
            hold = [[UILongPressGestureRecognizer alloc] initWithTarget:target() action:@selector(edgeHeld:)];
            hold.minimumPressDuration = 0.28;
            hold.cancelsTouchesInView = NO;
            [host addGestureRecognizer:hold];
            objc_setAssociatedObject(host, &kHoldKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (!SGFlag(SGKeyGestures, NO)) return;
    UITapGestureRecognizer *tap = objc_getAssociatedObject(host, &kTapKey);
    if (!tap) {
        tap = [[UITapGestureRecognizer alloc] initWithTarget:target() action:@selector(doubleTapped:)];
        tap.numberOfTapsRequired = 2;
        [host addGestureRecognizer:tap];
        objc_setAssociatedObject(host, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *seen = objc_getAssociatedObject(host, &kSeenKey);
    NSUInteger now = tapsAbove(host);
    if (seen.unsignedIntegerValue == now) return;
    objc_setAssociatedObject(host, &kSeenKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    yieldSingleTaps(host, tap);
}

#pragma mark - hooks

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client {
    id controller = %orig;
    sg_player = controller;
    return controller;
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTNowPlayingPlaybackControllerImplementation"]);
}
