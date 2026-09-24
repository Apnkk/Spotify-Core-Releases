#import "AppIconSettings.h"
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"

static NSString *const kSGAppIconKey = @"spotifyglass.appicon";

NSInteger SGCurrentAppIconIndex(void) {
    NSInteger stored = SGInt(kSGAppIconKey, 0);
    if (stored >= 0 && stored <= 17) return stored;
    return 0;
}

NSString *SGCurrentAppIconLabel(void) {
    NSInteger idx = SGCurrentAppIconIndex();
    if (idx == 0) return @"Default";
    return [NSString stringWithFormat:@"Ares %02ld", (long)idx];
}

static UIImage *SGDefaultIconThumbnail(void) {
    for (NSString *name in @[@"AppIcon60x60", @"AppIcon76x76", @"AppIcon", @"Icon"]) {
        UIImage *img = [UIImage imageNamed:name];
        if (img) return img;
        NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
        if (p) {
            img = [UIImage imageWithContentsOfFile:p];
            if (img) return img;
        }
    }
    CGSize size = CGSizeMake(44, 44);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 44, 44) cornerRadius:10] fill];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
        UIImage *sym = [[UIImage systemImageNamed:@"music.note" withConfiguration:config] imageWithTintColor:UIColor.blackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize s = sym.size;
        [sym drawInRect:CGRectMake((44 - s.width) / 2, (44 - s.height) / 2, s.width, s.height)];
    }];
}

static UIImage *SGCustomIconThumbnail(NSInteger index) {
    NSString *name = [NSString stringWithFormat:@"spotify_logo_%02ld", (long)index];
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    if (path) {
        return [UIImage imageWithContentsOfFile:path];
    }
    return [UIImage imageNamed:name];
}

UIImage *SGCurrentAppIconImage(void) {
    NSInteger idx = SGCurrentAppIconIndex();
    if (idx >= 1 && idx <= 17) {
        UIImage *img = SGCustomIconThumbnail(idx);
        if (img) return img;
    }
    for (NSString *name in @[@"spotify_logo_01", @"ares_logo", @"AresLog", @"AppIcon60x60"]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
        if (path) {
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) return img;
        }
        UIImage *img = [UIImage imageNamed:name];
        if (img) return img;
    }
    return SGDefaultIconThumbnail();
}

@interface SGAppIconPage : SGPage
@end

@implementation SGAppIconPage {
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"App Icon";
    _footer = SGNote(@"Changes take effect immediately on your home screen.");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (_footer) SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 18;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = SGDequeueCell(tableView, @"app_icon_cell");
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    
    NSInteger currentIdx = SGCurrentAppIconIndex();
    BOOL isSelected = (indexPath.row == currentIdx);
    
    if (indexPath.row == 0) {
        content.text = @"Default";
        content.secondaryText = @"Spotify Classic Icon";
        content.image = SGDefaultIconThumbnail();
    } else {
        content.text = [NSString stringWithFormat:@"Ares Edition %02ld", (long)indexPath.row];
        content.secondaryText = @"Custom Spotify Core Icon";
        content.image = SGCustomIconThumbnail(indexPath.row);
    }
    
    content.textProperties.font = SGTitleFont();
    content.textProperties.color = UIColor.whiteColor;
    content.secondaryTextProperties.font = SGSubtitleFont();
    content.secondaryTextProperties.color = SGGrey();
    content.imageProperties.maximumSize = CGSizeMake(44, 44);
    content.imageProperties.cornerRadius = 10;
    content.imageToTextPadding = 14;
    
    cell.contentConfiguration = content;
    cell.backgroundColor = SGCardBackground();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    
    if (isSelected) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    } else {
        cell.accessoryView = nil;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (![[UIApplication sharedApplication] supportsAlternateIcons]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Icon"
            message:@"Alternate icons are not supported on this installation."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSString *iconName = (indexPath.row == 0) ? nil : [NSString stringWithFormat:@"spotify_logo_%02ld", (long)indexPath.row];
    NSInteger selectedRow = indexPath.row;
    
    [[UIApplication sharedApplication] setAlternateIconName:iconName completionHandler:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Icon"
                    message:error.localizedDescription
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                SGSetInt(kSGAppIconKey, selectedRow);
                [self.tableView reloadData];
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
                    NSString *splashBoard = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/SplashBoard"];
                    [[NSFileManager defaultManager] removeItemAtPath:splashBoard error:nil];
                    NSString *launchCache = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.apple.LaunchImage"];
                    [[NSFileManager defaultManager] removeItemAtPath:launchCache error:nil];
                });
            }
        });
    }];
}

@end

UIViewController *SGAppIconPickerPage(void) {
    return [SGAppIconPage new];
}

SGModRow *SGAppIconRow(void) {
    SGModRow *row = SGPageRow(@"App icon", ^UIViewController *{ return SGAppIconPickerPage(); });
    row.value = ^NSString *{ return SGCurrentAppIconLabel(); };
    return SGWithSymbol(row, @"app.badge");
}
