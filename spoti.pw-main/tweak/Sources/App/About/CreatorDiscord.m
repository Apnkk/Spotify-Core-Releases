#import "CreatorDiscord.h"
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"

static NSString *const kSGDiscordUserId = @"280054039536730112";
static NSString *const kSGDiscordNameKey = @"spotifyglass.discord.creator.name";
static NSString *const kSGDiscordTagKey = @"spotifyglass.discord.creator.tag";

static NSString *SGCachePath(void) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [dir stringByAppendingPathComponent:@"discord_creator_avatar.png"];
}

static UIImage *SGLoadInitialAvatar(void) {
    NSString *cache = SGCachePath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:cache]) {
        UIImage *img = [UIImage imageWithContentsOfFile:cache];
        if (img) return img;
    }
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"discord_creator_default" ofType:@"png"];
    if (bundled) {
        UIImage *img = [UIImage imageWithContentsOfFile:bundled];
        if (img) return img;
    }
    return [UIImage imageNamed:@"discord_creator_default"];
}

@implementation SGCreatorFooterView {
    UILabel *_headerLabel;
    UIControl *_card;
    UIImageView *_avatarView;
    UILabel *_nameLabel;
    UILabel *_tagLabel;
    UIImageView *_discordIcon;
    UILabel *_footerLabel;
}

- (instancetype)initWithFooterNote:(NSString *)footerNote {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;

    _headerLabel = [UILabel new];
    _headerLabel.text = @"CREATOR";
    _headerLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    _headerLabel.textColor = SGDiscordColor();
    [self addSubview:_headerLabel];

    _card = [UIControl new];
    _card.backgroundColor = SGCardBackground();
    _card.layer.cornerRadius = 16;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.clipsToBounds = YES;
    [_card addTarget:self action:@selector(cardTouchDown) forControlEvents:UIControlEventTouchDown];
    [_card addTarget:self action:@selector(cardTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_card addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_card];

    _avatarView = [UIImageView new];
    _avatarView.layer.cornerRadius = 22;
    _avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    _avatarView.layer.borderWidth = 2.0;
    _avatarView.layer.borderColor = [SGDiscordColor() colorWithAlphaComponent:0.8].CGColor;
    _avatarView.clipsToBounds = YES;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.image = SGLoadInitialAvatar();
    [_card addSubview:_avatarView];

    NSString *storedName = [[NSUserDefaults standardUserDefaults] stringForKey:kSGDiscordNameKey];
    _nameLabel = [UILabel new];
    _nameLabel.text = storedName.length ? storedName : @"Apnk";
    _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _nameLabel.textColor = UIColor.whiteColor;
    [_card addSubview:_nameLabel];

    NSString *storedTag = [[NSUserDefaults standardUserDefaults] stringForKey:kSGDiscordTagKey];
    _tagLabel = [UILabel new];
    _tagLabel.text = storedTag.length ? storedTag : @"@xw2tt · Tap to view profile";
    _tagLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _tagLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    [_card addSubview:_tagLabel];

    _discordIcon = SGSymbolView(@"bubble.left.and.bubble.right.fill", 15, UIImageSymbolWeightSemibold, 24);
    _discordIcon.tintColor = SGDiscordColor();
    [_card addSubview:_discordIcon];

    _footerLabel = [UILabel new];
    _footerLabel.text = footerNote ?: @"Modified by Ares — EeveeSpotify & spoti.pw Combined Edition";
    _footerLabel.font = SGSubtitleFont() ?: [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _footerLabel.textColor = SGGrey();
    _footerLabel.textAlignment = NSTextAlignmentCenter;
    _footerLabel.numberOfLines = 0;
    [self addSubview:_footerLabel];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat margin = 16.0;
    CGFloat contentWidth = width - (margin * 2);

    _headerLabel.frame = CGRectMake(margin + 4, 8, contentWidth, 16);
    _card.frame = CGRectMake(margin, 28, contentWidth, 68);

    _avatarView.frame = CGRectMake(12, 12, 44, 44);
    CGFloat textLeft = 12 + 44 + 12;
    CGFloat textRight = contentWidth - 44;
    CGFloat textW = MAX(50, textRight - textLeft);
    _nameLabel.frame = CGRectMake(textLeft, 14, textW, 20);
    _tagLabel.frame = CGRectMake(textLeft, 36, textW, 16);

    _discordIcon.frame = CGRectMake(contentWidth - 14 - 24, (68 - 24) / 2, 24, 24);

    CGFloat footerY = 28 + 68 + 14;
    CGSize footerSize = [_footerLabel sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
    _footerLabel.frame = CGRectMake(margin, footerY, contentWidth, footerSize.height);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = size.width;
    CGFloat contentWidth = width - 32;
    CGSize footerSize = [_footerLabel sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
    CGFloat total = 28 + 68 + 14 + footerSize.height + 24;
    return CGSizeMake(width, total);
}

- (void)cardTouchDown {
    [UIView animateWithDuration:0.15 animations:^{
        self->_card.alpha = 0.65;
        self->_card.transform = CGAffineTransformMakeScale(0.98, 0.98);
    }];
}

- (void)cardTouchUp {
    [UIView animateWithDuration:0.2 animations:^{
        self->_card.alpha = 1.0;
        self->_card.transform = CGAffineTransformIdentity;
    }];
}

- (void)cardTapped {
    NSURL *discordApp = [NSURL URLWithString:[NSString stringWithFormat:@"discord://-/users/%@", kSGDiscordUserId]];
    if ([[UIApplication sharedApplication] canOpenURL:discordApp]) {
        [[UIApplication sharedApplication] openURL:discordApp options:@{} completionHandler:nil];
    } else {
        SGOpenURL([NSString stringWithFormat:@"https://discord.dog/%@", kSGDiscordUserId]);
    }
}

- (void)refreshLive {
    static NSTimeInterval lastFetch = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastFetch < 15.0) return;
    lastFetch = now;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://discord.dog/%@", kSGDiscordUserId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8.0];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return;
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html) return;

        NSString *avatarUrl = nil;
        NSRegularExpression *reAvatar = [NSRegularExpression regularExpressionWithPattern:@"\"avatarUrl\":\"(https:[^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *mAvatar = [reAvatar firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
        if (mAvatar && mAvatar.numberOfRanges > 1) {
            avatarUrl = [html substringWithRange:[mAvatar rangeAtIndex:1]];
        }
        if (!avatarUrl) {
            NSRegularExpression *reImg = [NSRegularExpression regularExpressionWithPattern:@"\"image\":\"(https:[^\"]+)\"" options:0 error:nil];
            NSTextCheckingResult *mImg = [reImg firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            if (mImg && mImg.numberOfRanges > 1) {
                avatarUrl = [html substringWithRange:[mImg rangeAtIndex:1]];
            }
        }

        NSString *displayName = nil;
        NSRegularExpression *reName = [NSRegularExpression regularExpressionWithPattern:@"\"globalName\":\"([^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *mName = [reName firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
        if (mName && mName.numberOfRanges > 1) {
            displayName = [html substringWithRange:[mName rangeAtIndex:1]];
        }
        if (!displayName) {
            NSRegularExpression *rePerson = [NSRegularExpression regularExpressionWithPattern:@"\"name\":\"([^\"]+)\"" options:0 error:nil];
            NSTextCheckingResult *mPerson = [rePerson firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            if (mPerson && mPerson.numberOfRanges > 1) {
                displayName = [html substringWithRange:[mPerson rangeAtIndex:1]];
            }
        }

        NSString *username = nil;
        NSRegularExpression *reUser = [NSRegularExpression regularExpressionWithPattern:@"\"username\":\"([^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *mUser = [reUser firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
        if (mUser && mUser.numberOfRanges > 1) {
            username = [html substringWithRange:[mUser rangeAtIndex:1]];
        }

        if (avatarUrl) {
            NSString *pngUrl = [avatarUrl stringByReplacingOccurrencesOfString:@".gif" withString:@".png"];
            NSURL *imgUrl = [NSURL URLWithString:pngUrl];
            NSMutableURLRequest *imgReq = [NSMutableURLRequest requestWithURL:imgUrl cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8.0];
            [imgReq setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
            [[[NSURLSession sharedSession] dataTaskWithRequest:imgReq completionHandler:^(NSData *imgData, NSURLResponse *res, NSError *err) {
                UIImage *newImage = (imgData && !err) ? [UIImage imageWithData:imgData] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf applyProfileName:displayName username:username avatar:newImage avatarData:imgData];
                });
            }] resume];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf applyProfileName:displayName username:username avatar:nil avatarData:nil];
            });
        }
    }];
    [task resume];
}

- (void)applyProfileName:(NSString *)name username:(NSString *)user avatar:(UIImage *)avatar avatarData:(NSData *)avatarData {
    if (name.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:kSGDiscordNameKey];
        _nameLabel.text = name;
    }
    if (user.length > 0) {
        NSString *tag = [NSString stringWithFormat:@"@%@ · Tap to view profile", user];
        [[NSUserDefaults standardUserDefaults] setObject:tag forKey:kSGDiscordTagKey];
        _tagLabel.text = tag;
    }
    if (avatar && avatarData) {
        [avatarData writeToFile:SGCachePath() atomically:YES];
        [UIView transitionWithView:_avatarView duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self->_avatarView.image = avatar;
        } completion:nil];
    }
}

@end

UIView *SGCreatorFooter(NSString *footerNote) {
    return [[SGCreatorFooterView alloc] initWithFooterNote:footerNote];
}
