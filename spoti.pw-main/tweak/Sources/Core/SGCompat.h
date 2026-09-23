#import <UIKit/UIKit.h>

#ifndef SG_COMPAT_H
#define SG_COMPAT_H

typedef NS_ENUM(NSInteger, UIGlassEffectStyle) {
    UIGlassEffectStyleClear = 0,
    UIGlassEffectStyleRegular = 1
};

@interface UIGlassEffect : UIVisualEffect
+ (instancetype)effectWithStyle:(NSInteger)style;
@property (nonatomic, retain) UIColor *tintColor;
@end

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

@interface UIView (SGCornerCompat)
@property (nonatomic, retain) id cornerConfiguration;
- (void)setCornerConfiguration:(id)config;
@end

@interface MPMediaItemAnimatedArtwork : NSObject
- (instancetype)initWithArtworkID:(NSString *)artworkID
       previewImageRequestHandler:(void (^)(CGSize size, void (^done)(UIImage *image)))previewHandler
  videoAssetFileURLRequestHandler:(void (^)(CGSize size, void (^done)(NSURL *url)))videoHandler;
@end

@interface NSObject (SGMPNowPlayingInfoCenterCompat)
+ (NSArray<NSString *> *)supportedAnimatedArtworkKeys;
@end

#ifndef MPNowPlayingInfoProperty3x4AnimatedArtwork
#define MPNowPlayingInfoProperty3x4AnimatedArtwork @"MPNowPlayingInfoProperty3x4AnimatedArtwork"
#endif

#ifndef MPNowPlayingInfoProperty1x1AnimatedArtwork
#define MPNowPlayingInfoProperty1x1AnimatedArtwork @"MPNowPlayingInfoProperty1x1AnimatedArtwork"
#endif

#endif
