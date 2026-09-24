#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "App/About/AppIconSettings.h"
#import "SGSplashScreen.h"

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

%end

%ctor {
    %init;
}
