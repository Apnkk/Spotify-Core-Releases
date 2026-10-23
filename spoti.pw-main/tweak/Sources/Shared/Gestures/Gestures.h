// Double tap zones over the player's artwork, Hold edge to play faster, and AirPods head gestures.
#import <UIKit/UIKit.h>

#define SGKeyGestures               @"spotifyglass.gestures"
#define SGKeyGestureSplit           @"spotifyglass.gestures.split"
#define SGKeyGestureStep            @"spotifyglass.gestures.step"
#define SGKeyGestureZones           @"spotifyglass.gestures.zones"
#define SGKeyGestureHold            @"spotifyglass.gestures.hold"
#define SGKeyGestureHoldSpeed       @"spotifyglass.gestures.hold.speed"

#define SGKeyHeadGestures           @"spotifyglass.gestures.head"
#define SGKeyHeadGestureNod         @"spotifyglass.gestures.head.nod"
#define SGKeyHeadGestureShake       @"spotifyglass.gestures.head.shake"
#define SGKeyHeadGestureChime       @"spotifyglass.gestures.head.chime"
#define SGKeyHeadGestureSensitivity @"spotifyglass.gestures.head.sensitivity"
#define SGKeyHeadGestureLearned     @"spotifyglass.gestures.head.learned"

typedef NS_ENUM(NSInteger, SGGestureAction) {
    SGGestureNothing = 0,
    SGGestureSeekBack,
    SGGestureSeekForward,
    SGGesturePlayPause,
    SGGestureNextTrack,
    SGGesturePreviousTrack,
    SGGestureShuffle,
    SGGestureRepeat,
};

NSArray<NSString *> *SGGestureActionNames(void);
NSArray<NSString *> *SGGestureSplitNames(void);
NSArray<NSNumber *> *SGGestureStepChoices(void);
NSArray<NSNumber *> *SGGestureHoldSpeedChoices(void);

// The split and the seek step as indices into the lists above, and what they mean.
NSInteger SGGestureSplit(void);
NSInteger SGGestureStepChoice(void);
NSInteger SGGestureHoldSpeedChoice(void);
double SGGestureHoldSpeed(void);
// The split as a grid: 2x1, 3x1 or 3x3.
void SGGestureGrid(NSInteger *columns, NSInteger *rows);
double SGGestureStep(void);

// The action of every cell of the current split, row-major, one entry per cell.
NSArray<NSNumber *> *SGGestureZones(void);
void SGSetGestureZone(NSInteger cell, SGGestureAction action);
void SGResetGestureZones(void);
// Which cell of the current split holds `point`, in a view of size `size`.
NSInteger SGGestureCellAt(CGPoint point, CGSize size);

void SGGesturePerformAction(SGGestureAction action);

UIViewController *SGGesturesSettingsPage(void);
UIViewController *SGHeadGesturesSettingsPage(void);
NSString *SGHeadGesturesSummary(void);

// Told of each action a double tap is about to perform, before the player has acted on it; one observer,
// for a look that answers the gesture (the redesign's haptics). Main thread.
void SGGestureSetObserver(void (^observer)(SGGestureAction action));

// Puts the double tap and edge hold on `host`, the view the player's grid covers, while the switches are on.
void SGGestureAttach(UIView *host);
