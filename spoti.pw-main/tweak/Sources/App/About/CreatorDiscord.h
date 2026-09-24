#import <UIKit/UIKit.h>

@interface SGCreatorFooterView : UIView
- (instancetype)initWithFooterNote:(NSString *)footerNote;
- (void)refreshLive;
@end

UIView *SGCreatorFooter(NSString *footerNote);
