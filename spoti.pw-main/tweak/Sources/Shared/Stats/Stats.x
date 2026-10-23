// Listening stats: local play history tracker (>= 30s played), Your Stats dashboard,
// 24-hour activity chart, streaks, top songs/artists/albums, and Spotify JSON importer/exporter.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "Stats.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SGPlayEntry : NSObject
@property (nonatomic, copy) NSString *trackURI;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
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
    e.timestamp = [dict[@"ts"] respondsToSelector:@selector(doubleValue)] ? [dict[@"ts"] doubleValue] : 0;
    e.secondsPlayed = [dict[@"sec"] respondsToSelector:@selector(doubleValue)] ? [dict[@"sec"] doubleValue] : 0;
    return e.timestamp > 0 && e.secondsPlayed > 0 ? e : nil;
}

@end

#pragma mark - Storage & Watcher

@interface SGStatsStore : NSObject
@property (nonatomic, readonly) NSArray<SGPlayEntry *> *entries;
+ (instancetype)shared;
- (void)recordTrackURI:(NSString *)uri title:(NSString *)title artist:(NSString *)artist album:(NSString *)album seconds:(double)sec at:(NSTimeInterval)ts;
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
    double _accumulatedSeconds;
    NSTimeInterval _lastTick;
    BOOL _wasPlaying;
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

    __weak typeof(self) weakSelf = self;
    SGPlayerObserve(^(SPTPlayerState *state) {
        [weakSelf handlePlayerState:state];
    });
    return self;
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
        [self recordTrackURI:_activeURI
                       title:_activeTitle
                      artist:_activeArtist
                       album:_activeAlbum
                     seconds:_accumulatedSeconds
                          at:NSDate.date.timeIntervalSince1970];
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
    NSString *artist = [state.track respondsToSelector:@selector(artistTitle)] ? state.track.artistTitle : nil;
    NSString *album = [state.track respondsToSelector:@selector(albumTitle)] ? state.track.albumTitle : nil;
    if (!title.length) title = state.track.metadata[@"title"];
    if (!artist.length) artist = state.track.metadata[@"artist_name"];
    if (!album.length) album = state.track.metadata[@"album_title"];

    if (_activeURI && ![_activeURI isEqualToString:uri]) {
        [self flushCurrentTrack];
    }
    _activeURI = uri;
    _activeTitle = title ?: @"Unknown Track";
    _activeArtist = artist ?: @"Unknown Artist";
    _activeAlbum = album ?: @"";
    _wasPlaying = !state.isPaused;
    _lastTick = now;
}

- (void)recordTrackURI:(NSString *)uri title:(NSString *)title artist:(NSString *)artist album:(NSString *)album seconds:(double)sec at:(NSTimeInterval)ts {
    SGPlayEntry *e = [SGPlayEntry new];
    e.trackURI = uri ?: @"";
    e.title = title.length ? title : @"Unknown Track";
    e.artist = artist.length ? artist : @"Unknown Artist";
    e.album = album ?: @"";
    e.timestamp = ts;
    e.secondsPlayed = sec;
    [_entries addObject:e];
    [self saveToDisk];
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
        // Support both our own exported format and Spotify's Extended Streaming History / Account Data JSON
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
    if (imported > 0) [self saveToDisk];
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
}

@end

#pragma mark - 24-Hour Bar Chart View

@interface SGStatsHoursChartView : UIView
@property (nonatomic, copy) NSArray<NSNumber *> *hourMinutes;
@end

@implementation SGStatsHoursChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    return self;
}

- (void)setHourMinutes:(NSArray<NSNumber *> *)hourMinutes {
    _hourMinutes = [hourMinutes copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || _hourMinutes.count != 24) return;
    double maxVal = 1.0;
    for (NSNumber *n in _hourMinutes) if (n.doubleValue > maxVal) maxVal = n.doubleValue;

    CGFloat leftPad = 14, rightPad = 14, topPad = 12, bottomPad = 24;
    CGFloat chartW = rect.size.width - leftPad - rightPad;
    CGFloat chartH = rect.size.height - topPad - bottomPad;
    CGFloat colW = chartW / 24.0;

    for (int h = 0; h < 24; h++) {
        double val = _hourMinutes[(NSUInteger)h].doubleValue;
        CGFloat frac = (CGFloat)(val / maxVal);
        CGFloat barH = MAX(3.0, frac * chartH);
        CGRect bar = CGRectMake(leftPad + h * colW + 1.5, topPad + chartH - barH, MAX(2.5, colW - 3.0), barH);
        UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:2.0];
        UIColor *col = val > 0 ? [SGGreen() colorWithAlphaComponent:(CGFloat)(0.35 + 0.65 * frac)]
                               : [UIColor colorWithWhite:1.0 alpha:0.10];
        [col setFill];
        [bp fill];
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.45],
    };
    NSArray<NSNumber *> *marks = @[@0, @6, @12, @18, @23];
    NSArray<NSString *> *labels = @[@"0h", @"6h", @"12h", @"18h", @"23h"];
    for (NSUInteger i = 0; i < marks.count; i++) {
        int h = marks[i].intValue;
        NSString *lbl = labels[i];
        CGSize sz = [lbl sizeWithAttributes:attrs];
        CGFloat x = leftPad + h * colW + (colW - sz.width) * 0.5;
        [lbl drawAtPoint:CGPointMake(x, rect.size.height - bottomPad + 6) withAttributes:attrs];
    }
}

@end

#pragma mark - Your Stats Dashboard Page

static NSArray<SGModRow *> *rankedRowsFromCounts(NSDictionary<NSString *, NSNumber *> *secondsByKey,
                                                 NSDictionary<NSString *, NSString *> *subtitleByKey,
                                                 NSString *symbol) {
    NSArray<NSString *> *sorted = [secondsByKey keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    NSUInteger limit = MIN((NSUInteger)10, sorted.count);
    for (NSUInteger i = 0; i < limit; i++) {
        NSString *key = sorted[i];
        double mins = secondsByKey[key].doubleValue / 60.0;
        NSString *rankTitle = [NSString stringWithFormat:@"%lu. %@", (unsigned long)(i + 1), key];
        NSString *sub = subtitleByKey[key];
        SGModRow *row = SGWithSymbol(SGStatRow(rankTitle, ^NSString *{
            return [NSString stringWithFormat:@"%.0f min", fmax(1.0, mins)];
        }), symbol);
        row.subtitle = sub;
        [rows addObject:row];
    }
    if (!rows.count) {
        [rows addObject:SGStatRow(@"No plays recorded in this period yet", ^NSString *{ return @""; })];
    }
    return rows;
}

static void computeStreaks(NSArray<SGPlayEntry *> *entries, NSInteger *currentStreakOut, NSInteger *bestStreakOut) {
    if (!entries.count) {
        *currentStreakOut = 0;
        *bestStreakOut = 0;
        return;
    }
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSMutableSet<NSNumber *> *dayNumbers = [NSMutableSet set];
    for (SGPlayEntry *e in entries) {
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:e.timestamp];
        NSDate *startOfDay = [cal startOfDayForDate:d];
        NSInteger dayIdx = (NSInteger)llround(startOfDay.timeIntervalSince1970 / 86400.0);
        [dayNumbers addObject:@(dayIdx)];
    }
    NSArray<NSNumber *> *sortedDays = [dayNumbers.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSInteger best = 0, run = 0, prev = NSIntegerMin;
    for (NSNumber *day in sortedDays) {
        NSInteger d = day.integerValue;
        run = (d == prev + 1) ? (run + 1) : 1;
        if (run > best) best = run;
        prev = d;
    }
    NSDate *todayStart = [cal startOfDayForDate:NSDate.date];
    NSInteger todayIdx = (NSInteger)llround(todayStart.timeIntervalSince1970 / 86400.0);
    NSInteger cur = 0;
    NSInteger probe = [dayNumbers containsObject:@(todayIdx)] ? todayIdx : (todayIdx - 1);
    while ([dayNumbers containsObject:@(probe)]) {
        cur++;
        probe--;
    }
    *currentStreakOut = cur;
    *bestStreakOut = best;
}

UIViewController *SGStatsDashboardPage(void) {
    __weak __block SGModPage *weakPage = nil;
    __block NSInteger selectedPeriod = 1; // 0=7d, 1=30d, 2=6mo, 3=All time
    NSArray<NSString *> *periodNames = @[@"7 days", @"30 days", @"6 months", @"All time"];

    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Your stats" build:^NSArray<SGModSection *> *{
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSTimeInterval cutoff = 0;
        if (selectedPeriod == 0) cutoff = now - 7 * 86400.0;
        else if (selectedPeriod == 1) cutoff = now - 30 * 86400.0;
        else if (selectedPeriod == 2) cutoff = now - 180 * 86400.0;

        NSArray<SGPlayEntry *> *all = SGStatsStore.shared.entries;
        NSMutableArray<SGPlayEntry *> *filtered = [NSMutableArray array];
        double totalSeconds = 0;
        NSMutableArray<NSNumber *> *hourSeconds = [NSMutableArray arrayWithCapacity:24];
        for (int i = 0; i < 24; i++) [hourSeconds addObject:@0.0];

        NSMutableDictionary<NSString *, NSNumber *> *trackSec = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSString *> *trackSub = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *artistSec = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *albumSec = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSString *> *albumSub = [NSMutableDictionary dictionary];

        NSCalendar *cal = NSCalendar.currentCalendar;
        for (SGPlayEntry *e in all) {
            if (e.timestamp < cutoff) continue;
            [filtered addObject:e];
            totalSeconds += e.secondsPlayed;

            NSInteger hr = [cal component:NSCalendarUnitHour fromDate:[NSDate dateWithTimeIntervalSince1970:e.timestamp]];
            if (hr >= 0 && hr < 24) {
                hourSeconds[(NSUInteger)hr] = @(hourSeconds[(NSUInteger)hr].doubleValue + e.secondsPlayed / 60.0);
            }
            if (e.title.length) {
                trackSec[e.title] = @(trackSec[e.title].doubleValue + e.secondsPlayed);
                if (e.artist.length) trackSub[e.title] = e.artist;
            }
            if (e.artist.length) {
                artistSec[e.artist] = @(artistSec[e.artist].doubleValue + e.secondsPlayed);
            }
            if (e.album.length) {
                albumSec[e.album] = @(albumSec[e.album].doubleValue + e.secondsPlayed);
                if (e.artist.length) albumSub[e.album] = e.artist;
            }
        }

        NSInteger curStreak = 0, bestStreak = 0;
        computeStreaks(all, &curStreak, &bestStreak);

        SGModRow *periodRow = SGWithSymbol(SGStatActionRow(@"Time range", @"Tap to cycle period", ^NSString *{
            return periodNames[(NSUInteger)selectedPeriod];
        }, ^{
            selectedPeriod = (selectedPeriod + 1) % (NSInteger)periodNames.count;
            [weakPage rebuild];
        }), @"calendar");

        SGModRow *minsRow = SGWithSymbol(SGStatRow(@"Minutes listened", ^NSString *{
            return [NSString stringWithFormat:@"%.0f min", totalSeconds / 60.0];
        }), @"clock.fill");
        SGModRow *playsRow = SGWithSymbol(SGStatRow(@"Songs played", ^NSString *{
            return [NSString stringWithFormat:@"%lu", (unsigned long)filtered.count];
        }), @"music.note.list");
        SGModRow *streakRow = SGWithSymbol(SGStatRow(@"Current streak", ^NSString *{
            return [NSString stringWithFormat:@"%ld day%@", (long)curStreak, curStreak == 1 ? @"" : @"s"];
        }), @"flame.fill");
        SGModRow *bestRow = SGWithSymbol(SGStatRow(@"Best streak", ^NSString *{
            return [NSString stringWithFormat:@"%ld day%@", (long)bestStreak, bestStreak == 1 ? @"" : @"s"];
        }), @"trophy.fill");

        SGStatsHoursChartView *chart = [[SGStatsHoursChartView alloc] initWithFrame:CGRectMake(0, 0, 320, 124)];
        chart.hourMinutes = hourSeconds;

        return @[
            SGSection(@"Overview", @[periodRow, minsRow, playsRow, streakRow, bestRow]),
            SGSection(@"Listening by hour of day", @[SGCustomViewRow(chart, 124)]),
            SGSection(@"Top Songs", rankedRowsFromCounts(trackSec, trackSub, @"music.note")),
            SGSection(@"Top Artists", rankedRowsFromCounts(artistSec, nil, @"person.wave.2.fill")),
            SGSection(@"Top Albums", rankedRowsFromCounts(albumSec, albumSub, @"square.stack.fill")),
        ];
    }];
    weakPage = page;
    return page;
}

#pragma mark - Document Picker Helper for Import

@interface SGStatsImportDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) SGModPage *page;
@end

@implementation SGStatsImportDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSInteger totalImported = 0;
    for (NSURL *url in urls) {
        BOOL sec = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (sec) [url stopAccessingSecurityScopedResource];
        totalImported += [SGStatsStore.shared importSpotifyHistoryData:data];
    }
    [self.page rebuild];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Complete"
                                                                   message:[NSString stringWithFormat:@"Imported %ld listening entries.", (long)totalImported]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.page presentViewController:alert animated:YES completion:nil];
}

@end

static SGStatsImportDelegate *sg_importDelegate;

#pragma mark - Settings Page

BOOL SGStatsEnabled(void) {
    return SGEnabled(SGKeyStats);
}

NSString *SGStatsSummary(void) {
    if (!SGStatsEnabled()) return @"Off";
    NSUInteger count = SGStatsStore.shared.entries.count;
    return count > 0 ? [NSString stringWithFormat:@"%lu plays", (unsigned long)count] : @"On";
}

UIViewController *SGStatsSettingsPage(void) {
    __weak __block SGModPage *weakPage = nil;
    SGModPage *page = [[SGModPage alloc] initWithTitle:@"Listening stats" build:^NSArray<SGModSection *> *{
        SGModRow *enableRow = SGWithSymbol(SGSwitchRow(@"Record listening history", @"Locally records songs played for at least 30 seconds on this iPhone", SGKeyStats), @"chart.bar.fill");
        enableRow.glows = YES;

        SGModRow *dashboardRow = SGWithSymbol(SGPageRow(@"Your stats", ^UIViewController *{
            return SGStatsDashboardPage();
        }), @"sparkles");
        dashboardRow.value = ^NSString *{
            return [NSString stringWithFormat:@"%lu plays", (unsigned long)SGStatsStore.shared.entries.count];
        };

        SGModRow *importRow = SGWithSymbol(SGActionRow(@"Import Spotify data…", @"Import Streaming_History_Audio.json or exported stats JSON", ^{
            sg_importDelegate = [SGStatsImportDelegate new];
            sg_importDelegate.page = weakPage;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
            picker.allowsMultipleSelection = YES;
            picker.delegate = sg_importDelegate;
            [weakPage presentViewController:picker animated:YES completion:nil];
        }), @"square.and.arrow.down");

        SGModRow *exportRow = SGWithSymbol(SGActionRow(@"Export history…", @"Share your local listening history as JSON", ^{
            NSData *data = [SGStatsStore.shared exportJSONData];
            if (!data) return;
            NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SpotifyCore_ListeningStats.json"];
            [data writeToFile:tmpPath atomically:YES];
            NSURL *fileURL = [NSURL fileURLWithPath:tmpPath];
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
            [weakPage presentViewController:share animated:YES completion:nil];
        }), @"square.and.arrow.up");

        SGModRow *clearRow = SGWithSymbol(SGWarningRow(@"Clear history…", @"Delete all locally recorded listening stats", ^{
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Clear Listening History?"
                                                                             message:@"This will remove all locally recorded plays from this iPhone."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
                [SGStatsStore.shared clearAll];
                [weakPage rebuild];
            }]];
            [weakPage presentViewController:confirm animated:YES completion:nil];
        }), @"trash");

        return @[
            SGNotedSection(nil, @[enableRow, dashboardRow], @"All listening statistics are stored strictly on your iPhone and never uploaded anywhere."),
            SGSection(@"Data", @[importRow, exportRow, clearRow]),
        ];
    }];
    weakPage = page;
    return page;
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [SGStatsStore shared];
    });
}
