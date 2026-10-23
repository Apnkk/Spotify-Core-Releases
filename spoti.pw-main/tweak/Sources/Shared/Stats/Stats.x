// 1:1 Chroma 0.51.0 Listening Stats: SGStatsWatcher, SGStatsArtwork, SGStatsTopCell,
// SGStatsSummaryCell, SGStatsHoursCell, SGStatsShelfCell, SGStatsTile, SGStatsRowCell,
// and SGStatsPageController with Spotify JSON import/export and artwork resolution.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "Stats.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - Data Models

@interface SGPlayEntry : NSObject
@property (nonatomic, copy) NSString *trackURI;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic) double secondsPlayed;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@implementation SGPlayEntry

- (NSDictionary *)toDictionary {
    return @{
        @"uri": self.trackURI ?: @"",
        @"title": self.title ?: @"Unknown Track",
        @"artist": self.artist ?: @"Unknown Artist",
        @"album": self.album ?: @"",
        @"img": self.imageURL ?: @"",
        @"ts": @(self.timestamp),
        @"sec": @(self.secondsPlayed),
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    SGPlayEntry *e = [SGPlayEntry new];
    e.trackURI = [dict[@"uri"] isKindOfClass:NSString.class] ? dict[@"uri"] : @"";
    e.title = [dict[@"title"] isKindOfClass:NSString.class] ? dict[@"title"] : @"Unknown Track";
    e.artist = [dict[@"artist"] isKindOfClass:NSString.class] ? dict[@"artist"] : @"Unknown Artist";
    e.album = [dict[@"album"] isKindOfClass:NSString.class] ? dict[@"album"] : @"";
    e.imageURL = [dict[@"img"] isKindOfClass:NSString.class] ? dict[@"img"] : @"";
    e.timestamp = [dict[@"ts"] respondsToSelector:@selector(doubleValue)] ? [dict[@"ts"] doubleValue] : 0;
    e.secondsPlayed = [dict[@"sec"] respondsToSelector:@selector(doubleValue)] ? [dict[@"sec"] doubleValue] : 0;
    return (e.timestamp > 0 && e.secondsPlayed > 0) ? e : nil;
}

@end

@interface SGStatsAggregateItem : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *trackURI;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic) double seconds;
@property (nonatomic) NSInteger plays;
@end

@implementation SGStatsAggregateItem
@end

#pragma mark - Artwork Loader & Cache (SGStatsArtwork)

static NSString *SGNormalizeSpotifyImageURL(NSString *raw) {
    if (!raw.length) return nil;
    if ([raw hasPrefix:@"https://"] || [raw hasPrefix:@"http://"]) return raw;
    if ([raw hasPrefix:@"spotify:image:"]) {
        NSString *hex = [raw substringFromIndex:@"spotify:image:".length];
        if (hex.length) return [NSString stringWithFormat:@"https://i.scdn.co/image/%@", hex];
    }
    return nil;
}

@interface SGStatsArtwork : UIView
- (void)configureWithTitle:(NSString *)title imageURL:(NSString *)imageURL trackURI:(NSString *)trackURI circular:(BOOL)circular;
@end

@implementation SGStatsArtwork {
    UILabel *_initialLabel;
    UIImageView *_imageView;
    NSString *_currentTag;
}

static NSCache<NSString *, UIImage *> *sg_artCache(void) {
    static NSCache *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [NSCache new];
        c.countLimit = 250;
    });
    return c;
}

static NSMutableDictionary<NSString *, NSString *> *sg_uriToImageMap(void) {
    static NSMutableDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
    return m;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.clipsToBounds = YES;

    _initialLabel = [UILabel new];
    _initialLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    _initialLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    _initialLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_initialLabel];

    _imageView = [UIImageView new];
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.clipsToBounds = YES;
    [self addSubview:_imageView];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _initialLabel.frame = self.bounds;
    _imageView.frame = self.bounds;
}

- (void)configureWithTitle:(NSString *)title imageURL:(NSString *)imageURL trackURI:(NSString *)trackURI circular:(BOOL)circular {
    self.layer.cornerRadius = circular ? (self.bounds.size.width * 0.5) : 8.0;
    self.layer.cornerCurve = circular ? kCACornerCurveCircular : kCACornerCurveContinuous;
    _initialLabel.text = title.length ? [[title substringToIndex:1] uppercaseString] : @"♪";
    _imageView.image = nil;

    NSString *resolvedURL = SGNormalizeSpotifyImageURL(imageURL);
    if (!resolvedURL.length && trackURI.length) {
        @synchronized (sg_uriToImageMap()) {
            resolvedURL = sg_uriToImageMap()[trackURI];
        }
    }
    NSString *tag = resolvedURL.length ? resolvedURL : (trackURI ?: title ?: @"");
    _currentTag = [tag copy];

    if (resolvedURL.length) {
        UIImage *cached = [sg_artCache() objectForKey:resolvedURL];
        if (cached) {
            _imageView.image = cached;
            return;
        }
        [self fetchImageFromURLString:resolvedURL forTag:tag];
    } else if ([trackURI hasPrefix:@"spotify:track:"]) {
        NSString *oembed = [NSString stringWithFormat:@"https://open.spotify.com/oembed?url=%@", trackURI];
        NSURL *url = [NSURL URLWithString:oembed];
        if (!url) return;
        __weak typeof(self) weakSelf = self;
        [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (!data) return;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *thumb = [json isKindOfClass:NSDictionary.class] ? json[@"thumbnail_url"] : nil;
            if ([thumb isKindOfClass:NSString.class] && thumb.length) {
                @synchronized (sg_uriToImageMap()) {
                    sg_uriToImageMap()[trackURI] = thumb;
                }
                [weakSelf fetchImageFromURLString:thumb forTag:tag];
            }
        }] resume];
    }
}

- (void)fetchImageFromURLString:(NSString *)urlStr forTag:(NSString *)tag {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if (!img) return;
        [sg_artCache() setObject:img forKey:urlStr];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || ![strongSelf->_currentTag isEqualToString:tag]) return;
            strongSelf->_imageView.image = img;
        });
    }] resume];
}

@end

#pragma mark - Storage & Watcher (SGStatsStore)

@interface SGStatsStore : NSObject <SGPlayerStateObserver>
@property (nonatomic, readonly) NSArray<SGPlayEntry *> *entries;
+ (instancetype)shared;
- (NSInteger)importSpotifyHistoryData:(NSData *)data;
- (NSData *)exportJSONData;
- (void)clearAll;
@end

@implementation SGStatsStore {
    NSMutableArray<SGPlayEntry *> *_entries;
    NSString *_filePath;
    NSString *_activeURI;
    NSString *_activeTitle;
    NSString *_activeArtist;
    NSString *_activeAlbum;
    NSString *_activeImageURL;
    double _accumulatedSeconds;
    NSTimeInterval _lastTick;
    BOOL _wasPlaying;
    NSTimer *_tickTimer;
}

+ (instancetype)shared {
    static SGStatsStore *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [SGStatsStore new];
    });
    return inst;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"spotifyglass"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    _filePath = [dir stringByAppendingPathComponent:@"listening_stats.json"];
    _entries = [NSMutableArray array];
    [self loadFromDisk];

    SGAddPlayerStateObserver(self);
    _tickTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(pollCurrentState) userInfo:nil repeats:YES];
    return self;
}

- (void)pollCurrentState {
    [self handlePlayerState:SGPlayerState()];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self handlePlayerState:state];
}

- (NSArray<SGPlayEntry *> *)entries {
    return [_entries copy];
}

- (void)loadFromDisk {
    NSData *data = [NSData dataWithContentsOfFile:_filePath];
    if (!data) return;
    NSArray *raw = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![raw isKindOfClass:NSArray.class]) return;
    for (NSDictionary *d in raw) {
        SGPlayEntry *e = [SGPlayEntry fromDictionary:d];
        if (e) [_entries addObject:e];
    }
}

- (void)saveToDisk {
    NSMutableArray *raw = [NSMutableArray arrayWithCapacity:_entries.count];
    for (SGPlayEntry *e in _entries) [raw addObject:[e toDictionary]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:0 error:nil];
    if (data) [data writeToFile:_filePath atomically:YES];
}

- (void)flushCurrentTrack {
    if (_activeTitle.length && _accumulatedSeconds >= 30.0) {
        SGPlayEntry *e = [SGPlayEntry new];
        e.trackURI = _activeURI ?: @"";
        e.title = _activeTitle;
        e.artist = _activeArtist ?: @"Unknown Artist";
        e.album = _activeAlbum ?: @"";
        e.imageURL = _activeImageURL ?: @"";
        e.timestamp = NSDate.date.timeIntervalSince1970;
        e.secondsPlayed = _accumulatedSeconds;
        [_entries addObject:e];
        [self saveToDisk];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SGStatsDidUpdateNotification" object:nil];
    }
    _accumulatedSeconds = 0;
    _lastTick = 0;
}

- (void)handlePlayerState:(SPTPlayerState *)state {
    if (!SGStatsEnabled() || !state || !state.track) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (_wasPlaying && _lastTick > 0) {
        double delta = now - _lastTick;
        if (delta > 0 && delta < 30.0) _accumulatedSeconds += delta;
    }

    NSString *uri = SGURIString(state.track.URI) ?: @"";
    NSString *title = [state.track respondsToSelector:@selector(trackTitle)] ? state.track.trackTitle : nil;
    NSString *artist = [state.track respondsToSelector:@selector(artistName)] ? state.track.artistName : nil;
    NSString *album = state.track.metadata[@"album_title"];
    if (!title.length) title = state.track.metadata[@"title"];
    if (!artist.length) artist = state.track.metadata[@"artist_name"];

    NSString *imgURL = SGNormalizeSpotifyImageURL(state.track.metadata[@"image_xlarge_url"] ?: state.track.metadata[@"image_url"]);

    if (_activeURI && ![_activeURI isEqualToString:uri]) {
        [self flushCurrentTrack];
    }
    _activeURI = uri;
    _activeTitle = title ?: @"Unknown Track";
    _activeArtist = artist ?: @"Unknown Artist";
    _activeAlbum = album ?: @"";
    if (imgURL.length) _activeImageURL = imgURL;
    _wasPlaying = !state.isPaused;
    _lastTick = now;
}

- (NSInteger)importSpotifyHistoryData:(NSData *)data {
    if (!data) return 0;
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![arr isKindOfClass:NSArray.class]) return 0;

    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    df.dateFormat = @"yyyy-MM-dd HH:mm";

    NSInteger imported = 0;
    for (NSDictionary *item in arr) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        SGPlayEntry *own = [SGPlayEntry fromDictionary:item];
        if (own) {
            [_entries addObject:own];
            imported++;
            continue;
        }
        NSNumber *ms = item[@"ms_played"] ?: item[@"msPlayed"];
        if (![ms respondsToSelector:@selector(doubleValue)] || ms.doubleValue < 30000.0) continue;
        NSString *title = item[@"master_metadata_track_name"] ?: item[@"trackName"];
        NSString *artist = item[@"master_metadata_album_artist_name"] ?: item[@"artistName"];
        NSString *album = item[@"master_metadata_album_album_name"] ?: item[@"albumName"] ?: @"";
        NSString *uri = item[@"spotify_track_uri"] ?: @"";
        NSString *tsStr = item[@"ts"] ?: item[@"endTime"];
        if (![title isKindOfClass:NSString.class] || !title.length) continue;

        NSDate *date = [tsStr isKindOfClass:NSString.class] ? ([iso dateFromString:tsStr] ?: [df dateFromString:tsStr]) : nil;
        NSTimeInterval ts = date ? date.timeIntervalSince1970 : NSDate.date.timeIntervalSince1970;

        SGPlayEntry *e = [SGPlayEntry new];
        e.trackURI = [uri isKindOfClass:NSString.class] ? uri : @"";
        e.title = title;
        e.artist = [artist isKindOfClass:NSString.class] ? artist : @"Unknown Artist";
        e.album = [album isKindOfClass:NSString.class] ? album : @"";
        e.timestamp = ts;
        e.secondsPlayed = ms.doubleValue / 1000.0;
        [_entries addObject:e];
        imported++;
    }
    if (imported > 0) {
        [self saveToDisk];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SGStatsDidUpdateNotification" object:nil];
    }
    return imported;
}

- (NSData *)exportJSONData {
    NSMutableArray *raw = [NSMutableArray arrayWithCapacity:_entries.count];
    for (SGPlayEntry *e in _entries) [raw addObject:[e toDictionary]];
    return [NSJSONSerialization dataWithJSONObject:raw options:NSJSONWritingPrettyPrinted error:nil];
}

- (void)clearAll {
    [_entries removeAllObjects];
    [self saveToDisk];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SGStatsDidUpdateNotification" object:nil];
}

@end

#pragma mark - SGStatsTopCell (1:1 Chroma 0.51.0 4-Pill Period Selector)

@interface SGStatsTopCell : UITableViewCell
@property (nonatomic, copy) void (^periodChanged)(NSInteger index);
- (void)setSelectedPeriod:(NSInteger)index;
@end

@implementation SGStatsTopCell {
    NSArray<UIButton *> *_pills;
    NSInteger _selected;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    NSArray<NSString *> *titles = @[@"4 weeks", @"6 months", @"This year", @"All time"];
    NSMutableArray<UIButton *> *btns = [NSMutableArray arrayWithCapacity:4];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = (NSInteger)i;
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.layer.cornerRadius = 17.0;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b addTarget:self action:@selector(pillTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
        [btns addObject:b];
    }
    _pills = [btns copy];
    [self setSelectedPeriod:0];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat gap = 8.0;
    CGFloat pillW = (w - gap * 3.0) / 4.0;
    CGFloat pillH = 34.0;
    CGFloat y = (h - pillH) * 0.5;
    for (NSUInteger i = 0; i < _pills.count; i++) {
        _pills[i].frame = CGRectMake(i * (pillW + gap), y, pillW, pillH);
    }
}

- (void)setSelectedPeriod:(NSInteger)index {
    _selected = index;
    for (NSUInteger i = 0; i < _pills.count; i++) {
        BOOL active = ((NSInteger)i == index);
        UIButton *b = _pills[i];
        b.backgroundColor = active ? SGGreen() : SGCardSurfaceColor();
        [b setTitleColor:(active ? UIColor.blackColor : [UIColor colorWithWhite:1.0 alpha:0.75]) forState:UIControlStateNormal];
    }
}

- (void)pillTapped:(UIButton *)sender {
    if (sender.tag == _selected) return;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self setSelectedPeriod:sender.tag];
    if (self.periodChanged) self.periodChanged(sender.tag);
}

@end

#pragma mark - SGStatsSummaryCell (1:1 Chroma 0.51.0 Hero Minutes & 4-Stat Strip Card)

@interface SGStatsSummaryCell : UITableViewCell
- (void)configureWithMinutes:(NSInteger)minutes
                       plays:(NSInteger)plays
                       songs:(NSInteger)songs
                     artists:(NSInteger)artists
                      streak:(NSInteger)streak;
@end

@implementation SGStatsSummaryCell {
    UILabel *_bigNumber;
    UILabel *_unitLabel;
    UIView *_topDivider;
    NSArray<UILabel *> *_colValues;
    NSArray<UILabel *> *_colNames;
    NSArray<UIView *> *_colDividers;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = SGCardSurfaceColor();
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _bigNumber = [UILabel new];
    _bigNumber.font = [UIFont monospacedDigitSystemFontOfSize:36 weight:UIFontWeightBold];
    _bigNumber.textColor = UIColor.whiteColor;
    [self.contentView addSubview:_bigNumber];

    _unitLabel = [UILabel new];
    _unitLabel.text = @"minutes listened";
    _unitLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _unitLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.50];
    [self.contentView addSubview:_unitLabel];

    _topDivider = [UIView new];
    _topDivider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self.contentView addSubview:_topDivider];

    NSArray<NSString *> *titles = @[@"Plays", @"Songs", @"Artists", @"Day streak"];
    NSMutableArray<UILabel *> *vals = [NSMutableArray arrayWithCapacity:4];
    NSMutableArray<UILabel *> *names = [NSMutableArray arrayWithCapacity:4];
    NSMutableArray<UIView *> *divs = [NSMutableArray arrayWithCapacity:3];

    for (int i = 0; i < 4; i++) {
        UILabel *v = [UILabel new];
        v.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
        v.textColor = UIColor.whiteColor;
        v.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:v];
        [vals addObject:v];

        UILabel *n = [UILabel new];
        n.text = titles[(NSUInteger)i];
        n.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        n.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
        n.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:n];
        [names addObject:n];

        if (i < 3) {
            UIView *d = [UIView new];
            d.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
            [self.contentView addSubview:d];
            [divs addObject:d];
        }
    }
    _colValues = [vals copy];
    _colNames = [names copy];
    _colDividers = [divs copy];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    _bigNumber.frame = CGRectMake(20.0, 18.0, w - 40.0, 42.0);
    _unitLabel.frame = CGRectMake(20.0, 60.0, w - 40.0, 18.0);
    _topDivider.frame = CGRectMake(16.0, 94.0, w - 32.0, 0.5);

    CGFloat colW = w / 4.0;
    for (int i = 0; i < 4; i++) {
        _colValues[(NSUInteger)i].frame = CGRectMake(i * colW, 108.0, colW, 22.0);
        _colNames[(NSUInteger)i].frame = CGRectMake(i * colW, 132.0, colW, 14.0);
        if (i < 3) {
            _colDividers[(NSUInteger)i].frame = CGRectMake((i + 1) * colW, 108.0, 0.5, 38.0);
        }
    }
}

- (void)configureWithMinutes:(NSInteger)minutes
                       plays:(NSInteger)plays
                       songs:(NSInteger)songs
                     artists:(NSInteger)artists
                      streak:(NSInteger)streak {
    NSNumberFormatter *nf = [NSNumberFormatter new];
    nf.numberStyle = NSNumberFormatterDecimalStyle;
    _bigNumber.text = [nf stringFromNumber:@(minutes)] ?: @"0";
    _colValues[0].text = [nf stringFromNumber:@(plays)] ?: @"0";
    _colValues[1].text = [nf stringFromNumber:@(songs)] ?: @"0";
    _colValues[2].text = [nf stringFromNumber:@(artists)] ?: @"0";
    _colValues[3].text = [NSString stringWithFormat:@"%ldd", (long)streak];
    _colValues[3].textColor = (streak > 0) ? SGGreen() : UIColor.whiteColor;
}

@end

#pragma mark - SGStatsHoursCell (1:1 Chroma 0.51.0 24-Hour Activity Bar Chart Cell)

@interface SGStatsHoursCell : UITableViewCell
- (void)configureWithHourMinutes:(NSArray<NSNumber *> *)hourMinutes;
@end

@implementation SGStatsHoursCell {
    UILabel *_heading;
    UILabel *_peakNote;
    NSArray<UIView *> *_bars;
    NSArray<UILabel *> *_ticks;
    NSArray<NSNumber *> *_values;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = SGCardSurfaceColor();
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _heading = [UILabel new];
    _heading.text = @"WHEN YOU LISTEN";
    _heading.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    _heading.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    [self.contentView addSubview:_heading];

    _peakNote = [UILabel new];
    _peakNote.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _peakNote.textColor = SGGreen();
    _peakNote.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_peakNote];

    NSMutableArray<UIView *> *barArr = [NSMutableArray arrayWithCapacity:24];
    for (int i = 0; i < 24; i++) {
        UIView *b = [UIView new];
        b.layer.cornerRadius = 2.5;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:b];
        [barArr addObject:b];
    }
    _bars = [barArr copy];

    NSArray<NSString *> *lbls = @[@"12a", @"6a", @"12p", @"6p"];
    NSMutableArray<UILabel *> *tickArr = [NSMutableArray arrayWithCapacity:4];
    for (NSString *t in lbls) {
        UILabel *l = [UILabel new];
        l.text = t;
        l.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
        l.textColor = [UIColor colorWithWhite:1.0 alpha:0.38];
        [self.contentView addSubview:l];
        [tickArr addObject:l];
    }
    _ticks = [tickArr copy];

    return self;
}

- (void)configureWithHourMinutes:(NSArray<NSNumber *> *)hourMinutes {
    _values = [hourMinutes copy];
    double maxVal = 0.0;
    int bestHour = -1;
    for (int i = 0; i < (int)hourMinutes.count && i < 24; i++) {
        double v = hourMinutes[(NSUInteger)i].doubleValue;
        if (v > maxVal) {
            maxVal = v;
            bestHour = i;
        }
    }
    if (bestHour >= 0 && maxVal > 0.1) {
        int hr12 = bestHour % 12;
        if (hr12 == 0) hr12 = 12;
        NSString *ampm = (bestHour < 12) ? @"AM" : @"PM";
        _peakNote.text = [NSString stringWithFormat:@"Most around %d %@", hr12, ampm];
    } else {
        _peakNote.text = @"";
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    _heading.frame = CGRectMake(16.0, 14.0, 140.0, 14.0);
    _peakNote.frame = CGRectMake(156.0, 13.0, w - 172.0, 16.0);

    double maxVal = 1.0;
    for (NSNumber *n in _values) if (n.doubleValue > maxVal) maxVal = n.doubleValue;

    CGFloat left = 16.0, right = 16.0, top = 38.0, chartH = 74.0;
    CGFloat availW = w - left - right;
    CGFloat stepW = availW / 24.0;
    CGFloat barW = MAX(3.5, stepW - 3.5);

    for (int i = 0; i < 24; i++) {
        double v = (_values.count > (NSUInteger)i) ? _values[(NSUInteger)i].doubleValue : 0.0;
        CGFloat frac = (CGFloat)(v / maxVal);
        CGFloat bh = MAX(4.0, frac * chartH);
        UIView *b = _bars[(NSUInteger)i];
        b.frame = CGRectMake(left + i * stepW + (stepW - barW) * 0.5, top + chartH - bh, barW, bh);
        b.backgroundColor = (v > 0.01) ? [SGGreen() colorWithAlphaComponent:(CGFloat)(0.35 + 0.65 * frac)]
                                       : [UIColor colorWithWhite:1.0 alpha:0.09];
    }

    int hours[4] = { 0, 6, 12, 18 };
    for (int i = 0; i < 4; i++) {
        _ticks[(NSUInteger)i].frame = CGRectMake(left + hours[i] * stepW, top + chartH + 6.0, 32.0, 14.0);
    }
}

@end

#pragma mark - SGStatsTile & SGStatsShelfCell (1:1 Chroma 0.51.0 Horizontal Artwork Shelf)

@interface SGStatsTile : UIView
- (void)configureWithRank:(NSInteger)rank item:(SGStatsAggregateItem *)item circular:(BOOL)circular;
@end

@implementation SGStatsTile {
    SGStatsArtwork *_art;
    UILabel *_rankBadge;
    UILabel *_name;
    UILabel *_sub;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _art = [[SGStatsArtwork alloc] initWithFrame:CGRectMake(8, 4, 96, 96)];
    [self addSubview:_art];

    _rankBadge = [UILabel new];
    _rankBadge.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
    _rankBadge.textColor = UIColor.blackColor;
    _rankBadge.backgroundColor = SGGreen();
    _rankBadge.textAlignment = NSTextAlignmentCenter;
    _rankBadge.layer.cornerRadius = 10.0;
    _rankBadge.clipsToBounds = YES;
    [self addSubview:_rankBadge];

    _name = [UILabel new];
    _name.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _name.textColor = UIColor.whiteColor;
    _name.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_name];

    _sub = [UILabel new];
    _sub.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.48];
    _sub.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_sub];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _art.frame = CGRectMake((w - 92.0) * 0.5, 6.0, 92.0, 92.0);
    _rankBadge.frame = CGRectMake(_art.frame.origin.x, 6.0, 24.0, 20.0);
    _name.frame = CGRectMake(4.0, 104.0, w - 8.0, 18.0);
    _sub.frame = CGRectMake(4.0, 122.0, w - 8.0, 15.0);
}

- (void)configureWithRank:(NSInteger)rank item:(SGStatsAggregateItem *)item circular:(BOOL)circular {
    [_art configureWithTitle:item.title imageURL:item.imageURL trackURI:item.trackURI circular:circular];
    _rankBadge.text = [NSString stringWithFormat:@"#%ld", (long)rank];
    _name.text = item.title;
    NSInteger mins = MAX(1, (NSInteger)llround(item.seconds / 60.0));
    _sub.text = [NSString stringWithFormat:@"%ldm · %ld", (long)mins, (long)item.plays];
}

@end

@interface SGStatsShelfCell : UITableViewCell
- (void)configureWithItems:(NSArray<SGStatsAggregateItem *> *)items circular:(BOOL)circular;
@end

@implementation SGStatsShelfCell {
    UIScrollView *_scroll;
    NSMutableArray<SGStatsTile *> *_tiles;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = SGCardSurfaceColor();
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _scroll = [UIScrollView new];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.alwaysBounceHorizontal = YES;
    [self.contentView addSubview:_scroll];
    _tiles = [NSMutableArray array];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.contentView.bounds;
}

- (void)configureWithItems:(NSArray<SGStatsAggregateItem *> *)items circular:(BOOL)circular {
    for (UIView *v in _tiles) [v removeFromSuperview];
    [_tiles removeAllObjects];

    CGFloat tileW = 108.0, tileH = 144.0, pad = 12.0;
    for (NSUInteger i = 0; i < items.count; i++) {
        SGStatsTile *t = [[SGStatsTile alloc] initWithFrame:CGRectMake(pad + i * (tileW + 6.0), 8.0, tileW, tileH)];
        [t configureWithRank:(NSInteger)(i + 1) item:items[i] circular:circular];
        [_scroll addSubview:t];
        [_tiles addObject:t];
    }
    _scroll.contentSize = CGSizeMake(pad * 2.0 + items.count * (tileW + 6.0), tileH + 16.0);
}

@end

#pragma mark - SGStatsRowCell (1:1 Chroma 0.51.0 Ranked Track / Album Row Cell)

@interface SGStatsRowCell : UITableViewCell
- (void)configureWithRank:(NSInteger)rank item:(SGStatsAggregateItem *)item;
@end

@implementation SGStatsRowCell {
    UILabel *_rankLabel;
    SGStatsArtwork *_artwork;
    UILabel *_titleLabel;
    UILabel *_subLabel;
    UILabel *_minsLabel;
    UILabel *_playsLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) return nil;
    self.backgroundColor = SGCardSurfaceColor();

    UIView *sel = [UIView new];
    sel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    self.selectedBackgroundView = sel;

    _rankLabel = [UILabel new];
    _rankLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    _rankLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    _rankLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:_rankLabel];

    _artwork = [[SGStatsArtwork alloc] initWithFrame:CGRectMake(0, 0, 42, 42)];
    [self.contentView addSubview:_artwork];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = UIColor.whiteColor;
    [self.contentView addSubview:_titleLabel];

    _subLabel = [UILabel new];
    _subLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _subLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.50];
    [self.contentView addSubview:_subLabel];

    _minsLabel = [UILabel new];
    _minsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    _minsLabel.textColor = SGGreen();
    _minsLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_minsLabel];

    _playsLabel = [UILabel new];
    _playsLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    _playsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    _playsLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_playsLabel];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    _rankLabel.frame = CGRectMake(8.0, 0, 28.0, h);
    _artwork.frame = CGRectMake(38.0, (h - 42.0) * 0.5, 42.0, 42.0);
    _titleLabel.frame = CGRectMake(90.0, 11.0, w - 168.0, 19.0);
    _subLabel.frame = CGRectMake(90.0, 31.0, w - 168.0, 16.0);
    _minsLabel.frame = CGRectMake(w - 74.0, 12.0, 60.0, 18.0);
    _playsLabel.frame = CGRectMake(w - 74.0, 31.0, 60.0, 15.0);
}

- (void)configureWithRank:(NSInteger)rank item:(SGStatsAggregateItem *)item {
    _rankLabel.text = [NSString stringWithFormat:@"%ld", (long)rank];
    _rankLabel.textColor = (rank <= 3) ? SGGreen() : [UIColor colorWithWhite:1.0 alpha:0.42];
    [_artwork configureWithTitle:item.title imageURL:item.imageURL trackURI:item.trackURI circular:NO];
    _titleLabel.text = item.title;
    _subLabel.text = item.subtitle;
    NSInteger mins = MAX(1, (NSInteger)llround(item.seconds / 60.0));
    _minsLabel.text = [NSString stringWithFormat:@"%ldm", (long)mins];
    _playsLabel.text = [NSString stringWithFormat:@"%ld play%@", (long)item.plays, item.plays == 1 ? @"" : @"s"];
}

@end

#pragma mark - SGStatsPageController (1:1 Chroma 0.51.0 Full Stats ViewController)

@interface SGStatsPageController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@end

@implementation SGStatsPageController {
    UITableView *_tableView;
    NSInteger _periodIndex; // 0=4 weeks, 1=6 months, 2=This year, 3=All time

    NSInteger _totalMinutes;
    NSInteger _totalPlays;
    NSInteger _uniqueSongs;
    NSInteger _uniqueArtists;
    NSInteger _dayStreak;
    NSArray<NSNumber *> *_hourMinutes;
    NSArray<SGStatsAggregateItem *> *_topArtists;
    NSArray<SGStatsAggregateItem *> *_topSongs;
    NSArray<SGStatsAggregateItem *> *_topAlbums;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Listening stats";
    self.view.backgroundColor = SGPageBackgroundColor();

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.backgroundColor = SGPageBackgroundColor();
    _tableView.separatorColor = SGHairlineColor();
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];

    [self setupMenuButton];
    [self recomputeStats];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recomputeStats) name:@"SGStatsDidUpdateNotification" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupMenuButton {
    __weak typeof(self) weakSelf = self;
    UIAction *toggleRecord = [UIAction actionWithTitle:(SGStatsEnabled() ? @"Recording On" : @"Recording Paused")
                                                 image:[UIImage systemImageNamed:(SGStatsEnabled() ? @"checkmark.circle.fill" : @"pause.circle")]
                                            identifier:nil
                                               handler:^(__kindof UIAction *action) {
        SGSetEnabled(SGKeyStats, !SGStatsEnabled());
        [weakSelf setupMenuButton];
    }];
    UIAction *importAct = [UIAction actionWithTitle:@"Import Spotify data…"
                                              image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *action) {
        [weakSelf promptImport];
    }];
    UIAction *exportAct = [UIAction actionWithTitle:@"Export history…"
                                              image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *action) {
        [weakSelf promptExport];
    }];
    UIAction *clearAct = [UIAction actionWithTitle:@"Clear history…"
                                             image:[UIImage systemImageNamed:@"trash"]
                                        identifier:nil
                                           handler:^(__kindof UIAction *action) {
        [weakSelf promptClear];
    }];
    clearAct.attributes = UIMenuElementAttributesDestructive;

    UIMenu *menu = [UIMenu menuWithTitle:@"" children:@[toggleRecord, importAct, exportAct, clearAct]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:menu];
}

- (void)recomputeStats {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval cutoff = 0;
    NSCalendar *cal = NSCalendar.currentCalendar;

    if (_periodIndex == 0) {
        cutoff = now - 28.0 * 86400.0;
    } else if (_periodIndex == 1) {
        cutoff = now - 180.0 * 86400.0;
    } else if (_periodIndex == 2) {
        NSDateComponents *comps = [cal components:NSCalendarUnitYear fromDate:NSDate.date];
        comps.month = 1;
        comps.day = 1;
        NSDate *jan1 = [cal dateFromComponents:comps];
        cutoff = jan1 ? jan1.timeIntervalSince1970 : (now - 365.0 * 86400.0);
    }

    NSArray<SGPlayEntry *> *all = SGStatsStore.shared.entries;
    double totalSec = 0;
    NSInteger playsCount = 0;
    NSMutableArray<NSNumber *> *hours = [NSMutableArray arrayWithCapacity:24];
    for (int i = 0; i < 24; i++) [hours addObject:@0.0];

    NSMutableDictionary<NSString *, SGStatsAggregateItem *> *songsMap = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, SGStatsAggregateItem *> *artistsMap = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, SGStatsAggregateItem *> *albumsMap = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *allDays = [NSMutableSet set];

    for (SGPlayEntry *e in all) {
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:e.timestamp];
        NSDate *startOfDay = [cal startOfDayForDate:d];
        [allDays addObject:@((NSInteger)llround(startOfDay.timeIntervalSince1970 / 86400.0))];

        if (e.timestamp < cutoff) continue;
        playsCount++;
        totalSec += e.secondsPlayed;

        NSInteger hr = [cal component:NSCalendarUnitHour fromDate:d];
        if (hr >= 0 && hr < 24) {
            hours[(NSUInteger)hr] = @(hours[(NSUInteger)hr].doubleValue + e.secondsPlayed / 60.0);
        }

        if (e.title.length) {
            NSString *sKey = [NSString stringWithFormat:@"%@||%@", e.title, e.artist ?: @""];
            SGStatsAggregateItem *item = songsMap[sKey];
            if (!item) {
                item = [SGStatsAggregateItem new];
                item.key = sKey;
                item.title = e.title;
                item.subtitle = e.artist ?: @"Unknown Artist";
                songsMap[sKey] = item;
            }
            item.seconds += e.secondsPlayed;
            item.plays += 1;
            if (e.trackURI.length && !item.trackURI.length) item.trackURI = e.trackURI;
            if (e.imageURL.length && !item.imageURL.length) item.imageURL = e.imageURL;
        }

        if (e.artist.length) {
            SGStatsAggregateItem *item = artistsMap[e.artist];
            if (!item) {
                item = [SGStatsAggregateItem new];
                item.key = e.artist;
                item.title = e.artist;
                item.subtitle = @"Artist";
                artistsMap[e.artist] = item;
            }
            item.seconds += e.secondsPlayed;
            item.plays += 1;
            if (e.trackURI.length && !item.trackURI.length) item.trackURI = e.trackURI;
            if (e.imageURL.length && !item.imageURL.length) item.imageURL = e.imageURL;
        }

        if (e.album.length) {
            NSString *aKey = [NSString stringWithFormat:@"%@||%@", e.album, e.artist ?: @""];
            SGStatsAggregateItem *item = albumsMap[aKey];
            if (!item) {
                item = [SGStatsAggregateItem new];
                item.key = aKey;
                item.title = e.album;
                item.subtitle = e.artist ?: @"";
                albumsMap[aKey] = item;
            }
            item.seconds += e.secondsPlayed;
            item.plays += 1;
            if (e.trackURI.length && !item.trackURI.length) item.trackURI = e.trackURI;
            if (e.imageURL.length && !item.imageURL.length) item.imageURL = e.imageURL;
        }
    }

    NSComparisonResult (^cmp)(SGStatsAggregateItem *, SGStatsAggregateItem *) = ^NSComparisonResult(SGStatsAggregateItem *a, SGStatsAggregateItem *b) {
        if (b.seconds > a.seconds) return NSOrderedDescending;
        if (b.seconds < a.seconds) return NSOrderedAscending;
        return NSOrderedSame;
    };

    NSArray<SGStatsAggregateItem *> *sortedArtists = [artistsMap.allValues sortedArrayUsingComparator:cmp];
    NSArray<SGStatsAggregateItem *> *sortedSongs = [songsMap.allValues sortedArrayUsingComparator:cmp];
    NSArray<SGStatsAggregateItem *> *sortedAlbums = [albumsMap.allValues sortedArrayUsingComparator:cmp];

    _totalMinutes = (NSInteger)llround(totalSec / 60.0);
    _totalPlays = playsCount;
    _uniqueSongs = (NSInteger)songsMap.count;
    _uniqueArtists = (NSInteger)artistsMap.count;
    _hourMinutes = [hours copy];
    _topArtists = [sortedArtists subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)12, sortedArtists.count))];
    _topSongs = [sortedSongs subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)15, sortedSongs.count))];
    _topAlbums = [sortedAlbums subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)10, sortedAlbums.count))];

    // Compute current day streak
    NSDate *todayStart = [cal startOfDayForDate:NSDate.date];
    NSInteger todayIdx = (NSInteger)llround(todayStart.timeIntervalSince1970 / 86400.0);
    NSInteger streak = 0;
    NSInteger probe = [allDays containsObject:@(todayIdx)] ? todayIdx : (todayIdx - 1);
    while ([allDays containsObject:@(probe)]) {
        streak++;
        probe--;
    }
    _dayStreak = streak;

    [_tableView reloadData];
}

#pragma mark - TableView DataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // Period Pills + Summary Hero + 24-Hour Chart
    if (section == 1) return 1; // Top Artists Horizontal Shelf
    if (section == 2) return MAX(1, (NSInteger)_topSongs.count);
    if (section == 3) return MAX(1, (NSInteger)_topAlbums.count);
    return 3; // Data Management (Import, Export, Clear)
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"Top artists";
    if (section == 2) return @"Top songs";
    if (section == 3) return @"Top albums";
    if (section == 4) return @"History & Data";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return 52.0;
        if (indexPath.row == 1) return 162.0;
        return 140.0;
    }
    if (indexPath.section == 1) return _topArtists.count ? 160.0 : 52.0;
    if (indexPath.section == 2) return _topSongs.count ? 60.0 : 52.0;
    if (indexPath.section == 3) return _topAlbums.count ? 60.0 : 52.0;
    return 50.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            SGStatsTopCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Top"];
            if (!cell) cell = [[SGStatsTopCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Top"];
            [cell setSelectedPeriod:_periodIndex];
            __weak typeof(self) weakSelf = self;
            cell.periodChanged = ^(NSInteger idx) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf->_periodIndex = idx;
                [strongSelf recomputeStats];
            };
            return cell;
        }
        if (indexPath.row == 1) {
            SGStatsSummaryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Sum"];
            if (!cell) cell = [[SGStatsSummaryCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Sum"];
            [cell configureWithMinutes:_totalMinutes plays:_totalPlays songs:_uniqueSongs artists:_uniqueArtists streak:_dayStreak];
            return cell;
        }
        SGStatsHoursCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Hrs"];
        if (!cell) cell = [[SGStatsHoursCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Hrs"];
        [cell configureWithHourMinutes:_hourMinutes];
        return cell;
    }

    if (indexPath.section == 1) {
        if (!_topArtists.count) return [self emptyCellInTableView:tableView text:@"Play songs for 30s or import your Spotify history"];
        SGStatsShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Shelf"];
        if (!cell) cell = [[SGStatsShelfCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Shelf"];
        [cell configureWithItems:_topArtists circular:YES];
        return cell;
    }

    if (indexPath.section == 2) {
        if (!_topSongs.count) return [self emptyCellInTableView:tableView text:@"No top songs in this period yet"];
        SGStatsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Row"];
        if (!cell) cell = [[SGStatsRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Row"];
        [cell configureWithRank:(indexPath.row + 1) item:_topSongs[(NSUInteger)indexPath.row]];
        return cell;
    }

    if (indexPath.section == 3) {
        if (!_topAlbums.count) return [self emptyCellInTableView:tableView text:@"No top albums in this period yet"];
        SGStatsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Row"];
        if (!cell) cell = [[SGStatsRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Row"];
        [cell configureWithRank:(indexPath.row + 1) item:_topAlbums[(NSUInteger)indexPath.row]];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Act"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Act"];
        cell.backgroundColor = SGCardSurfaceColor();
    }
    if (indexPath.row == 0) {
        cell.textLabel.text = @"Import Spotify data…";
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.detailTextLabel.text = @"Streaming_History_Audio.json or exported stats JSON";
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
        cell.imageView.tintColor = SGGreen();
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"Export history…";
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.detailTextLabel.text = @"Save or share your local listening history";
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
        cell.imageView.tintColor = SGGreen();
    } else {
        cell.textLabel.text = @"Clear history…";
        cell.textLabel.textColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
        cell.imageView.tintColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0];
    }
    return cell;
}

- (UITableViewCell *)emptyCellInTableView:(UITableView *)tableView text:(NSString *)text {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Empty"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Empty"];
        cell.backgroundColor = SGCardSurfaceColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        cell.textLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    }
    cell.textLabel.text = text;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2 && (NSUInteger)indexPath.row < _topSongs.count) {
        NSString *uri = _topSongs[(NSUInteger)indexPath.row].trackURI;
        if (uri.length) {
            NSURL *url = [NSURL URLWithString:uri];
            if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        }
        return;
    }
    if (indexPath.section == 4) {
        if (indexPath.row == 0) [self promptImport];
        else if (indexPath.row == 1) [self promptExport];
        else if (indexPath.row == 2) [self promptClear];
    }
}

#pragma mark - Import / Export / Clear Actions

- (void)promptImport {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSInteger totalImported = 0;
    for (NSURL *url in urls) {
        BOOL sec = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (sec) [url stopAccessingSecurityScopedResource];
        totalImported += [SGStatsStore.shared importSpotifyHistoryData:data];
    }
    [self recomputeStats];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Complete"
                                                                   message:[NSString stringWithFormat:@"Imported %ld listening plays.", (long)totalImported]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptExport {
    NSData *data = [SGStatsStore.shared exportJSONData];
    if (!data) return;
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Spotify_ListeningStats.json"];
    [data writeToFile:tmpPath atomically:YES];
    NSURL *fileURL = [NSURL fileURLWithPath:tmpPath];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    [self presentViewController:share animated:YES completion:nil];
}

- (void)promptClear {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Clear Listening History?"
                                                                     message:@"This will delete all locally recorded listening stats on this iPhone."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [SGStatsStore.shared clearAll];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

@end

#pragma mark - Public Entry Points

BOOL SGStatsEnabled(void) {
    return SGEnabled(SGKeyStats);
}

NSString *SGStatsSummary(void) {
    if (!SGStatsEnabled()) return @"Off";
    NSUInteger count = SGStatsStore.shared.entries.count;
    return count > 0 ? [NSString stringWithFormat:@"%lu plays", (unsigned long)count] : @"On";
}

UIViewController *SGStatsDashboardPage(void) {
    return [SGStatsPageController new];
}

UIViewController *SGStatsSettingsPage(void) {
    return [SGStatsPageController new];
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [SGStatsStore shared];
    });
}
