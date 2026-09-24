#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "App/About/AppIconSettings.h"
#import "SGSplashScreen.h"

@interface SGSplashOverlayView : UIView
@property (nonatomic, strong) UIImageView *logoView;
@end

@implementation SGSplashOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithRed:0.0706 green:0.0706 blue:0.0706 alpha:1.0];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.userInteractionEnabled = NO;

        CGFloat iconSize = 115.0;
        _logoView = [[UIImageView alloc] initWithFrame:CGRectMake((frame.size.width - iconSize) / 2.0,
                                                                 (frame.size.height - iconSize) / 2.0,
                                                                 iconSize,
                                                                 iconSize)];
        _logoView.contentMode = UIViewContentModeScaleAspectFit;
        _logoView.layer.cornerRadius = 24.0;
        _logoView.layer.masksToBounds = YES;
        _logoView.autoresizingMask = (UIViewAutoresizingFlexibleLeftMargin |
                                     UIViewAutoresizingFlexibleRightMargin |
                                     UIViewAutoresizingFlexibleTopMargin |
                                     UIViewAutoresizingFlexibleBottomMargin);
        _logoView.image = SGCurrentAppIconImage();
        [self addSubview:_logoView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat iconSize = 115.0;
    _logoView.bounds = CGRectMake(0, 0, iconSize, iconSize);
    _logoView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

@end

static SGSplashOverlayView *gSplashOverlay = nil;
static BOOL gSplashShown = NO;
static BOOL gSplashDismissed = NO;

void SGDismissSplash(void);

void SGShowSplashIfNeeded(UIWindow *window) {
    if (gSplashShown || !window) return;
    gSplashShown = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gSplashDismissed) return;

        CGRect bounds = window.bounds;
        if (CGRectIsEmpty(bounds) || bounds.size.width <= 0) {
            bounds = [UIScreen mainScreen].bounds;
        }

        gSplashOverlay = [[SGSplashOverlayView alloc] initWithFrame:bounds];
        [window addSubview:gSplashOverlay];
        [window bringSubviewToFront:gSplashOverlay];

        // Safety fallback timer to ensure dismissal after 1.5s max
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGDismissSplash();
        });
    });
}

void SGDismissSplash(void) {
    if (gSplashDismissed) return;
    gSplashDismissed = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gSplashOverlay) return;

        [UIView animateWithDuration:0.35
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            gSplashOverlay.alpha = 0.0;
        } completion:^(BOOL finished) {
            [gSplashOverlay removeFromSuperview];
            gSplashOverlay = nil;
        }];
    });
}

static void replaceLogosInView(UIView *view, UIImage *logo) {
    if (!view || !logo) return;
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)view;
        if (iv.bounds.size.width > 30.0 && iv.bounds.size.height > 30.0) {
            iv.image = logo;
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.layer.cornerRadius = 24.0;
            iv.layer.masksToBounds = YES;
        }
    }
    for (UIView *sub in view.subviews) {
        replaceLogosInView(sub, logo);
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (gSplashShown) {
        return;
    }

    NSString *cls = NSStringFromClass(self.class);
    if ([cls containsString:@"MainWindow"] ||
        [cls containsString:@"SPT"] ||
        self.isKeyWindow) {
        SGShowSplashIfNeeded(self);
    }
}

- (void)setRootViewController:(UIViewController *)rootViewController {
    %orig;
    if (!gSplashShown && self.isKeyWindow) {
        SGShowSplashIfNeeded(self);
    }
}

%end

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    NSString *cls = NSStringFromClass(self.class);
    if ([cls containsString:@"Launch"] || [cls containsString:@"Splash"]) {
        UIImage *logo = SGCurrentAppIconImage();
        if (logo) {
            replaceLogosInView(self.view, logo);
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *cls = NSStringFromClass(self.class);
    if (![cls containsString:@"Launch"] && ![cls containsString:@"Splash"]) {
        SGDismissSplash();
    }
}

%end

%hook _TtC23NavigationUI_TabBarImpl10TabBarView

- (void)layoutSubviews {
    %orig;
    SGDismissSplash();
}

%end

%ctor {
    %init;
}
