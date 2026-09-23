#import "SGGlass.h"
#import "SGRuntime.h"

// +effectWithStyle: is the only initialiser UIGlassEffect has; a bare -init leaves the material
// unresolved and the pane renders as a plain blur, while the capsule shape, which is the view's
// own property, still comes out right. Spotify's own Reprise glass builds its effect the same way.
UIVisualEffect *SGGlassEffect(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if ([glass respondsToSelector:@selector(effectWithStyle:)]) return [glass effectWithStyle:0];
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
}

static UIVisualEffectView *newPane(void) {
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
    glass.userInteractionEnabled = NO;
    // A pane goes in at index 0, but a host that rebuilds its content puts that in at index 0 too
    // and the pane would end up over it. Depth keeps a pane behind whatever the host draws.
    glass.layer.zPosition = -1;
    return glass;
}

UIVisualEffectView *SGGlassFor(UIView *host, const void *key) {
    UIVisualEffectView *glass = objc_getAssociatedObject(host, key);
    if (!glass) {
        glass = newPane();
        objc_setAssociatedObject(host, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != host) [host insertSubview:glass atIndex:0];
    return glass;
}

static char kPanesKey;

UIVisualEffectView *SGGlassAt(UIView *host, NSUInteger index) {
    NSMutableArray<UIVisualEffectView *> *panes = objc_getAssociatedObject(host, &kPanesKey);
    if (!panes) {
        panes = [NSMutableArray array];
        objc_setAssociatedObject(host, &kPanesKey, panes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    while (panes.count <= index) [panes addObject:newPane()];
    UIVisualEffectView *glass = panes[index];
    glass.hidden = NO;
    if (glass.superview != host) [host insertSubview:glass atIndex:0];
    return glass;
}

void SGHideGlassFrom(UIView *host, NSUInteger count) {
    NSArray<UIVisualEffectView *> *panes = objc_getAssociatedObject(host, &kPanesKey);
    for (NSUInteger i = count; i < panes.count; i++) panes[i].hidden = YES;
}

void SGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule) {
    Class config = NSClassFromString(@"UICornerConfiguration");
    Class cornerRadius = NSClassFromString(@"UICornerRadius");
    id shape = nil;
    SEL setCornerSel = NSSelectorFromString(@"setCornerConfiguration:");
    if (config && [glass respondsToSelector:setCornerSel]) {
        SEL capsuleSel = NSSelectorFromString(@"capsuleConfiguration");
        SEL uniformSel = NSSelectorFromString(@"configurationWithUniformRadius:");
        SEL fixedSel = NSSelectorFromString(@"fixedRadius:");
        if (capsule && [config respondsToSelector:capsuleSel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            shape = [config performSelector:capsuleSel];
            #pragma clang diagnostic pop
        } else if ([config respondsToSelector:uniformSel] && [cornerRadius respondsToSelector:fixedSel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id fixed = [cornerRadius performSelector:fixedSel withObject:(__bridge id)(void *)(intptr_t)radius];
            shape = [config performSelector:uniformSel withObject:fixed];
            #pragma clang diagnostic pop
        }
    }
    if (shape) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [glass performSelector:setCornerSel withObject:shape];
        #pragma clang diagnostic pop
        glass.clipsToBounds = NO;
    } else {
        glass.layer.cornerRadius = capsule ? glass.bounds.size.height / 2 : radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
    }
}
