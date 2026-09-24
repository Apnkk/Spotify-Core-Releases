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

static NSString *SGCachedDiscordName(void) {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kSGDiscordNameKey];
    return stored.length ? stored : @"Apnk";
}

static NSString *SGCachedDiscordTag(void) {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kSGDiscordTagKey];
    return stored.length ? stored : @"@xw2tt · Discord";
}

static void SGFetchDiscordProfile(SGModRow *row) {
    static NSTimeInterval lastFetch = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastFetch < 30.0) return;
    lastFetch = now;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://discord.dog/%@", kSGDiscordUserId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8.0];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)" forHTTPHeaderField:@"User-Agent"];

    __weak SGModRow *weakRow = row;
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

        void (^applyUpdates)(UIImage *img, NSData *imgData) = ^(UIImage *img, NSData *imgData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL changed = NO;
                if (displayName.length > 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:displayName forKey:kSGDiscordNameKey];
                    if (weakRow) weakRow.title = displayName;
                    changed = YES;
                }
                if (username.length > 0) {
                    NSString *tag = [NSString stringWithFormat:@"@%@ · Discord", username];
                    [[NSUserDefaults standardUserDefaults] setObject:tag forKey:kSGDiscordTagKey];
                    if (weakRow) weakRow.subtitle = tag;
                    changed = YES;
                }
                if (img && imgData) {
                    [imgData writeToFile:SGCachePath() atomically:YES];
                    if (weakRow) weakRow.image = img;
                    changed = YES;
                }
                if (changed) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SGCreatorProfileUpdated" object:nil];
                }
            });
        };

        if (avatarUrl) {
            NSString *pngUrl = [avatarUrl stringByReplacingOccurrencesOfString:@".gif" withString:@".png"];
            NSURL *imgUrl = [NSURL URLWithString:pngUrl];
            NSMutableURLRequest *imgReq = [NSMutableURLRequest requestWithURL:imgUrl cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8.0];
            [imgReq setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
            [[[NSURLSession sharedSession] dataTaskWithRequest:imgReq completionHandler:^(NSData *imgData, NSURLResponse *res, NSError *err) {
                UIImage *newImage = (imgData && !err) ? [UIImage imageWithData:imgData] : nil;
                applyUpdates(newImage, imgData);
            }] resume];
        } else {
            applyUpdates(nil, nil);
        }
    }];
    [task resume];
}

SGModSection *SGCreatorSection(void) {
    SGModRow *row = [SGModRow new];
    row.title = SGCachedDiscordName();
    row.subtitle = SGCachedDiscordTag();
    row.image = SGLoadInitialAvatar();
    row.circularImage = YES;

    UIImageView *discordIcon = SGSymbolView(@"bubble.left.and.bubble.right.fill", 15, UIImageSymbolWeightSemibold, 24);
    discordIcon.tintColor = SGDiscordColor();
    row.accessory = discordIcon;

    row.action = ^{
        NSURL *discordApp = [NSURL URLWithString:[NSString stringWithFormat:@"discord://-/users/%@", kSGDiscordUserId]];
        if ([[UIApplication sharedApplication] canOpenURL:discordApp]) {
            [[UIApplication sharedApplication] openURL:discordApp options:@{} completionHandler:nil];
        } else {
            SGOpenURL([NSString stringWithFormat:@"https://discord.dog/%@", kSGDiscordUserId]);
        }
    };

    SGFetchDiscordProfile(row);

    return SGSection(@"CREATOR", @[row]);
}
