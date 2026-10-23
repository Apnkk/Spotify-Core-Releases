#import <UIKit/UIKit.h>

UIViewController *SGLocalFilesEditorPage(void);
void SGPresentLocalTrackEditorForPath(NSString *filePath, UIViewController *presenter, void (^onSaved)(void));
