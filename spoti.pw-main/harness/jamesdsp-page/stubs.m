// The engine side of JamesDSP.h (JamesDSP.x in the tweak) the harness does not compile: a made-up status,
// a few fake files in a temporary library, and a smooth curve through the gains instead of the filter's
// real response. The page draws what these answer, so they answer the way the engine is documented to.
#import "Core/SGCore.h"
#import "JamesDSP.h"
#import "JamesDSPEngine.h"

void SGDSPApply(NSString *effect) {
    NSLog(@"[harness] apply %@", effect);
}

NSString *SGDSPStatus(void) {
    if (!SGDSPSwitch(SGKeyDSP)) return @"Off";
    // Alternates, so the page's once a second refresh can be seen working.
    return (long)NSDate.date.timeIntervalSince1970 % 6 < 3 ? @"Running · 44.1 kHz · 3% load" : @"Running · 44.1 kHz · 4% load";
}

// A chosen file whose name has "broken" in it did not take, the way a script that does not compile would not.
NSString *SGDSPError(NSString *switchKey) {
    NSDictionary<NSString *, NSString *> *files = @{
        SGKeyDSPLiveprog: SGKeyDSPLiveprogFile, SGKeyDSPConvolver: SGKeyDSPConvolverFile, SGKeyDSPDDC: SGKeyDSPDDCFile,
    };
    NSString *fileKey = files[switchKey];
    if (fileKey && [SGDSPString(fileKey) containsString:@"broken"]) {
        return [NSString stringWithFormat:@"%@, line 14: syntax error near \"spl0 =\"", SGDSPString(fileKey)];
    }
    if ([switchKey isEqualToString:SGKeyDSPGraphicEq] && ![SGDSPString(SGKeyDSPGraphicEqNodes) hasPrefix:@"GraphicEQ:"]) {
        return @"Not a GraphicEQ line: it starts with \"GraphicEQ:\"";
    }
    return nil;
}

#pragma mark - file libraries

static NSString *folderName(SGDSPFileKind kind) {
    return kind == SGDSPFileImpulseResponse ? @"Convolver" : kind == SGDSPFileDDC ? @"DDC" : @"Liveprog";
}

NSArray<NSString *> *SGDSPFileExtensions(SGDSPFileKind kind) {
    if (kind == SGDSPFileImpulseResponse) return @[@"wav", @"flac", @"irs"];
    return kind == SGDSPFileDDC ? @[@"vdc"] : @[@"eel"];
}

NSString *SGDSPLibraryDirectory(SGDSPFileKind kind) {
    NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"JamesDSPStandIn"] stringByAppendingPathComponent:folderName(kind)];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:path]) return path;
    [files createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray<NSString *> *shipped = kind == SGDSPFileImpulseResponse ? @[@"Concert hall.wav", @"Headphone crossfeed.irs", @"Small room.flac"]
                                 : kind == SGDSPFileDDC ? @[@"Beyerdynamic DT 770.vdc", @"Sennheiser HD 600.vdc"]
                                 : @[@"Bass enhancer.eel", @"Stereo panning.eel", @"Tape saturation broken.eel", @"Vinyl noise.eel"];
    for (NSString *name in shipped) {
        [[@"stand-in" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[path stringByAppendingPathComponent:name] atomically:YES];
    }
    return path;
}

NSArray<NSString *> *SGDSPLibraryFiles(SGDSPFileKind kind) {
    NSArray<NSString *> *extensions = SGDSPFileExtensions(kind);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:SGDSPLibraryDirectory(kind) error:nil]) {
        if ([extensions containsObject:name.pathExtension.lowercaseString]) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

NSString *SGDSPImportFile(SGDSPFileKind kind, NSURL *url, NSError **error) {
    NSString *name = url.lastPathComponent;
    if (![SGDSPFileExtensions(kind) containsObject:name.pathExtension.lowercaseString]) {
        if (error) *error = [NSError errorWithDomain:@"JamesDSP" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not a file of this kind."}];
        return nil;
    }
    NSString *target = [SGDSPLibraryDirectory(kind) stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager removeItemAtPath:target error:nil];
    if (![NSFileManager.defaultManager copyItemAtPath:url.path toPath:target error:error]) return nil;
    return name;
}

BOOL SGDSPDeleteFile(SGDSPFileKind kind, NSString *name) {
    return [NSFileManager.defaultManager removeItemAtPath:[SGDSPLibraryDirectory(kind) stringByAppendingPathComponent:name] error:nil];
}

#pragma mark - curves

// Catmull-Rom through the points on a log frequency axis, flat past the ends: smooth, and through every gain.
static void smoothCurve(const double *bands, NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *values) {
    NSInteger n = (NSInteger)gains.count;
    for (NSInteger i = 0; i < count; i++) {
        double f = 20 * pow(1000, count > 1 ? (double)i / (count - 1) : 0);
        frequencies[i] = f;
        double x = log(f);
        if (x <= log(bands[0])) { values[i] = gains[0].doubleValue; continue; }
        if (x >= log(bands[n - 1])) { values[i] = gains[n - 1].doubleValue; continue; }
        NSInteger k = 0;
        while (k < n - 2 && x > log(bands[k + 1])) k++;
        double t = (x - log(bands[k])) / (log(bands[k + 1]) - log(bands[k]));
        double p0 = gains[MAX(k - 1, 0)].doubleValue, p1 = gains[k].doubleValue;
        double p2 = gains[k + 1].doubleValue, p3 = gains[MIN(k + 2, n - 1)].doubleValue;
        values[i] = 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
    }
}

void SGDSPEqualizerResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *decibels) {
    smoothCurve(SGDSPEqualizerFrequencies, gains, count, frequencies, decibels);
}

void SGDSPCompanderResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *values) {
    smoothCurve(SGDSPCompanderFrequencies, gains, count, frequencies, values);
}
