#import <UIKit/UIKit.h>

#ifndef SG_COMPAT_H
#define SG_COMPAT_H

typedef NS_ENUM(NSInteger, UIGlassEffectStyle) {
    UIGlassEffectStyleClear = 0,
    UIGlassEffectStyleRegular = 1
};

@interface NSObject (SGScrollEdgeEffectStyleCompat)
+ (id)softStyle;
@end

@interface NSObject (SGScrollEdgeEffectCompat)
@property (nonatomic, retain) id style;
@end

@interface UIScrollView (SGCompat)
@property (nonatomic, readonly) id topEdgeEffect;
@end

@interface UIVisualEffect (SGGlassEffectCompat)
+ (id)effectWithStyle:(NSInteger)style;
@property (nonatomic, retain) UIColor *tintColor;
@end

@interface UIButtonConfiguration (SGCompat)
+ (instancetype)prominentGlassButtonConfiguration;
+ (instancetype)glassButtonConfiguration;
@end

@interface NSObject (SGUICornerRadiusCompat)
+ (id)fixedRadius:(CGFloat)radius;
@end

@interface NSObject (SGUICornerConfigurationCompat)
+ (id)capsuleConfiguration;
+ (id)configurationWithUniformRadius:(id)radius;
@end

@interface UIView (SGCompat)
@property (nonatomic, retain) id cornerConfiguration;
- (void)setCornerConfiguration:(id)config;
@end

#endif
