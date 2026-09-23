// Soft top edge: iOS 27 resolves a scroll view's automatic top edge effect to the hard style, the
// flat dark band under the navigation bar (UIKit.ScrollEdgeEffectView in trees/continuous/1.txt).
// Setting the soft style brings back iOS 26's thin fading blur. Set on every layout pass as well as
// on arrival, in case UIKit resolves the style again after the page appears.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"

typedef id (*SGMsgSendId)(id, SEL);
typedef void (*SGMsgSendVoidId)(id, SEL, id);

static id sg_send_id(id object, SEL selector) {
    return ((SGMsgSendId)objc_msgSend)(object, selector);
}

static void sg_send_void_id(id object, SEL selector, id value) {
    ((SGMsgSendVoidId)objc_msgSend)(object, selector, value);
}

static void soften(UIScrollView *scrollView) {
    if (@available(iOS 26.0, *)) {
        static char setKey;
        SEL topEdgeEffectSelector = NSSelectorFromString(@"topEdgeEffect");
        if (![scrollView respondsToSelector:topEdgeEffectSelector]) return;
        id top = sg_send_id(scrollView, topEdgeEffectSelector);
        if (!top) return;

        SEL styleSelector = NSSelectorFromString(@"style");
        SEL setStyleSelector = NSSelectorFromString(@"setStyle:");
        if (![top respondsToSelector:styleSelector] || ![top respondsToSelector:setStyleSelector]) {
            return;
        }

        id currentStyle = sg_send_id(top, styleSelector);
        if (currentStyle == objc_getAssociatedObject(scrollView, &setKey)) {
            return;
        }

        Class styleClass = NSClassFromString(@"UIScrollEdgeEffectStyle");
        SEL softStyleSelector = NSSelectorFromString(@"softStyle");
        if (!styleClass || ![styleClass respondsToSelector:softStyleSelector]) {
            return;
        }

        id softStyle = sg_send_id((id)styleClass, softStyleSelector);
        if (!softStyle) return;

        sg_send_void_id(top, setStyleSelector, softStyle);
        id appliedStyle = sg_send_id(top, styleSelector);
        objc_setAssociatedObject(
            scrollView,
            &setKey,
            appliedStyle,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"soft top edge: first scroll view %@", NSStringFromClass(scrollView.class)); });
    }
}

%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    if (self.window) soften(self);
}

- (void)layoutSubviews {
    %orig;
    if (self.window) soften(self);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
}
