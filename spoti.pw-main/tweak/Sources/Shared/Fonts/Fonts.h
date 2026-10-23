#import <UIKit/UIKit.h>

#define SGKeyFont           @"spotifyglass.font"
#define SGKeyFontCustomName @"spotifyglass.font.custom.name"
#define SGKeyFontCustomFile @"spotifyglass.font.custom.file"

NSString *SGFontSummary(void);
UIViewController *SGFontSettingsPage(void);
UIFont *SGTransformFontIfNeeded(UIFont *font);
