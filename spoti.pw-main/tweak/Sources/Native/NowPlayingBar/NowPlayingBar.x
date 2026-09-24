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
    if (!view || !SGFlag(@"spotifyglass.native.glass", YES)) return;
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

    UIVisualEffectView *glass = SGGlassFor(view, &kNativeNPBGlassKey);
    if (glass) {
        glass.frame = view.bounds;
        glass.layer.zPosition = -1;
        glass.layer.cornerRadius = 10;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) {
            glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        view.layer.cornerRadius = 10;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
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

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
