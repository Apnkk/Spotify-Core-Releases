#import <UIKit/UIKit.h>

#ifndef SG_COMPAT_H
#define SG_COMPAT_H

typedef NS_ENUM(NSInteger, UIGlassEffectStyle) {
    UIGlassEffectStyleClear = 0,
    UIGlassEffectStyleRegular = 1
};

@interface UIScrollEdgeEffectStyle : NSObject
+ (instancetype)softStyle;
@end

@interface UIScrollEdgeEffect : NSObject
@property (nonatomic, retain) UIScrollEdgeEffectStyle *style;
@end

@interface UIScrollView (SGCompat)
@property (nonatomic, readonly) UIScrollEdgeEffect *topEdgeEffect;
@end

@interface UIGlassEffect : UIVisualEffect
+ (instancetype)effectWithStyle:(UIGlassEffectStyle)style;
@property (nonatomic, retain) UIColor *tintColor;
@end

@interface UIButtonConfiguration (SGCompat)
+ (instancetype)prominentGlassButtonConfiguration;
+ (instancetype)glassButtonConfiguration;
@end

@interface UICornerRadius : NSObject
+ (instancetype)fixedRadius:(CGFloat)radius;
@end

@interface UICornerConfiguration : NSObject
+ (instancetype)capsuleConfiguration;
+ (instancetype)configurationWithUniformRadius:(id)radius;
@end

@interface UIView (SGCompat)
@property (nonatomic, retain) id cornerConfiguration;
- (void)setCornerConfiguration:(id)config;
@end

#endif
