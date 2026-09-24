// The device button of Spotify's own now playing bar, hidden on request.
//
// Tree (trees/test6.txt): the button row is a UIStackView holding Connect_EntryPointsImpl.ConnectStateView
// (the connected device) and .ConnectButtonView, each wrapped; hiding the wrapper closes the gap.
// The ConnectStateView under the title ("playing on ...") sits in InformationContainer and stays.
#import "Core/SGCore.h"
#import "NowPlayingBar.h"

static BOOL insideClass(UIView *view, NSString *marker) {
    for (UIView *v = view; v; v = v.superview) if ([NSStringFromClass(v.class) containsString:marker]) return YES;
    return NO;
}

static void hideConnectButton(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = NSStringFromClass(v.class);
        if (![name containsString:@"ConnectButtonView"] && ![name containsString:@"ConnectStateView"]) return;
        if (insideClass(v, @"InformationContainer")) return;
        UIView *item = v;
        while (item.superview && ![item.superview isKindOfClass:UIStackView.class]) item = item.superview;
        if (item.superview && !item.hidden) item.hidden = YES;
    });
}

static char kNativeNPBGlassKey;

static void applyNativeNPBGlass(UIView *view) {
    if (!view) return;
    BOOL enabled = SGFlag(@"spotifyglass.native.glass", YES);
    UIVisualEffectView *glass = objc_getAssociatedObject(view, &kNativeNPBGlassKey);

    if (!enabled) {
        if (glass) glass.hidden = YES;
        view.layer.borderWidth = 0;
        view.layer.shadowOpacity = 0;
        return;
    }

    if (view.superview) {
        view.superview.backgroundColor = UIColor.clearColor;
        view.superview.layer.backgroundColor = NULL;
    }
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = NULL;

    // Clear background colors on child subviews so the glass material shines through,
    // preserving labels, buttons, image views and the progress bar.
    SGForEachView(view, ^(UIView *v) {
        if ([v isKindOfClass:UIVisualEffectView.class]) return;
        if ([v isKindOfClass:UIControl.class] || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UILabel.class]) return;
        if (v.bounds.size.height <= 3) return; // keep progress indicator
        v.backgroundColor = UIColor.clearColor;
        v.layer.backgroundColor = NULL;
    });

    if (!glass) {
        glass = SGGlassFor(view, &kNativeNPBGlassKey);
    }
    if (glass) {
        glass.hidden = NO;
        glass.frame = view.bounds;
        glass.layer.zPosition = -1;
        glass.layer.cornerRadius = 12;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        glass.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        glass.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        glass.layer.borderWidth = 0.5;
        if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) {
            glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }

        view.layer.cornerRadius = 12;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
        view.layer.borderWidth = 0.5;
        view.layer.shadowColor = UIColor.blackColor.CGColor;
        view.layer.shadowOpacity = 0.35f;
        view.layer.shadowRadius = 8.0f;
        view.layer.shadowOffset = CGSizeMake(0, 3);
        view.clipsToBounds = NO;
    }
}

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *view = ((UIViewController *)self).view;
    if (SGHidden(SGHideBarConnect)) hideConnectButton(view);
    applyNativeNPBGlass(view);
}
%end

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    vc.view.backgroundColor = UIColor.clearColor;
    vc.view.layer.backgroundColor = NULL;
    for (UIViewController *child in vc.childViewControllers) {
        if ([NSStringFromClass(child.class) containsString:@"NowPlayingBarViewController"]) {
            applyNativeNPBGlass(child.view);
        }
    }
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
    ]);
}
