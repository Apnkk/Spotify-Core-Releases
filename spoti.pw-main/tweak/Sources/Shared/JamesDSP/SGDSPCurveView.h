// The equalizer's 15 bands or the compressor's 7 points, drawn as the response they make over a grid of
// their range, with a handle per band: dragged up and down it stores as it moves, a double tap puts it back
// to zero, and VoiceOver adjusts it a step at a time. Over it, Reset, and for the equalizer JamesDSP's
// presets in a pull-down named after the one the bands match.
#import <UIKit/UIKit.h>

@interface SGDSPCurveView : UIView
// SGKeyDSPEqualizerGains or SGKeyDSPCompanderGains.
- (instancetype)initWithKey:(NSString *)key;
// The stored gains again, and the curve for the stored filter type.
- (void)reload;
// The height the table gives its row.
+ (CGFloat)heightForKey:(NSString *)key;
@end
