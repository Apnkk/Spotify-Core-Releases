// What drives the native look's navbar: Spotify's tab bar composed on its layout passes (Navbar.x), and
// holding Home opens Mod Settings.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Settings/SGPage.h"

@interface SGHomeHold : UILongPressGestureRecognizer
@end

@implementation SGHomeHold
+ (void)held:(SGHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGHomeHold alloc] initWithTarget:SGHomeHold.class action:@selector(held:)]];
}

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

static char kNativeTabBarGlassKey;
static char kNativeTabBarRimKey;

static void applyNativeTabBarGlass(UIView *bar) {
    if (!bar) return;
    BOOL enabled = SGFlag(@"spotifyglass.native.glass", YES);
    UIVisualEffectView *glass = objc_getAssociatedObject(bar, &kNativeTabBarGlassKey);
    CALayer *rim = objc_getAssociatedObject(bar, &kNativeTabBarRimKey);

    if (!enabled) {
        if (glass) glass.hidden = YES;
        if (rim) rim.hidden = YES;
        return;
    }

    for (UIView *p = bar; p; p = p.superview) {
        p.backgroundColor = UIColor.clearColor;
        p.layer.backgroundColor = NULL;
        if ([NSStringFromClass(p.class) containsString:@"TabBarContainer"]) break;
    }

    for (UIView *sub in bar.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) continue;
        sub.backgroundColor = UIColor.clearColor;
        sub.layer.backgroundColor = NULL;
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:UIVisualEffectView.class]) continue;
            if (![inner isKindOfClass:UIControl.class] && ![inner isKindOfClass:UIImageView.class] && ![inner isKindOfClass:UILabel.class]) {
                inner.backgroundColor = UIColor.clearColor;
                inner.layer.backgroundColor = NULL;
            }
        }
    }

    if (!glass) {
        glass = SGGlassFor(bar, &kNativeTabBarGlassKey);
    }
    if (glass) {
        glass.hidden = NO;
        glass.frame = bar.bounds;
        glass.layer.zPosition = -1;
        if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) {
            glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        glass.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    }

    if (!rim) {
        rim = [CALayer layer];
        rim.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        [bar.layer addSublayer:rim];
        objc_setAssociatedObject(bar, &kNativeTabBarRimKey, rim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    rim.hidden = NO;
    rim.frame = CGRectMake(0, 0, bar.bounds.size.width, 0.5);
    rim.zPosition = 100;
}

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGComposeTabBar((UIView *)self);
    holdHome((UIView *)self);
    applyNativeTabBarGlass((UIView *)self);
    SGLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGComposeTabBar(bar);
    holdHome(bar);
    SGLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
    ]);
}
