// JamesDSP's settings: what each key holds until set, its bounds, and the lists the page's choices pick
// from. The values, ranges and lists are RootlessJamesDSP's (its preferences and arrays.xml), so a setup
// described for it reads the same here.
#import "Core/SGCore.h"
#import "JamesDSP.h"
#import "JamesDSPEngine.h"

const double SGDSPEqualizerFrequencies[15] = {25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000};
const double SGDSPEqualizerGainLimit = 12;
const double SGDSPCompanderFrequencies[7] = {95, 200, 400, 800, 1600, 3400, 7500};
const double SGDSPCompanderGainLimit = 1.2;

#pragma mark - the keys

typedef struct {
    NSString *__unsafe_unretained key;
    SGDSPRange range;
} SGDSPNumberKey;

static const SGDSPNumberKey kNumbers[] = {
    {SGKeyDSPPostGain,               {-15, 15, 0, 0.5}},
    {SGKeyDSPLimiterThreshold,       {-60, -0.1, -0.1, 0.1}},
    {SGKeyDSPLimiterRelease,         {1.5, 500, 60, 0.5}},
    {SGKeyDSPCompanderTime,          {0.06, 0.3, 0.22, 0.01}},
    {SGKeyDSPCompanderGranularity,   {0, 4, 2, 1}},
    {SGKeyDSPCompanderTransform,     {0, 3, 0, 1}},
    {SGKeyDSPBassGain,               {3, 15, 5, 0.5}},
    {SGKeyDSPEqualizerFilter,        {0, 5, 0, 1}},
    {SGKeyDSPEqualizerInterpolation, {0, 1, 0, 1}},
    {SGKeyDSPConvolverMode,          {0, 2, 0, 1}},
    {SGKeyDSPReverbPreset,           {0, 12, 9, 1}},    // Plate high, RootlessJamesDSP's
    {SGKeyDSPStereoWideLevel,        {30, 75, 60, 1}},
    {SGKeyDSPCrossfeedMode,          {0, 5, 5, 1}},     // Realistic surround, RootlessJamesDSP's
    {SGKeyDSPTubeDrive,              {-3, 12, 2, 0.5}},
};

static NSDictionary<NSString *, NSString *> *stringDefaults(void) {
    static NSDictionary<NSString *, NSString *> *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            SGKeyDSPCompanderGains: @"0;0;0;0;0;0;0",
            SGKeyDSPEqualizerGains: @"0;0;0;0;0;0;0;0;0;0;0;0;0;0;0",
            SGKeyDSPGraphicEqNodes: @"GraphicEQ: 0.0 0.0;",
            SGKeyDSPConvolverFile: @"",
            SGKeyDSPConvolverWaveEdit: @"-80;-100;0;0;0;0",
            SGKeyDSPDDCFile: @"",
            SGKeyDSPLiveprogFile: @"",
        };
    });
    return defaults;
}

// The switches of the effects, each the prefix of its own keys' names.
static NSArray<NSString *> *effectSwitches(void) {
    return @[SGKeyDSPCompander, SGKeyDSPBass, SGKeyDSPEqualizer, SGKeyDSPGraphicEq, SGKeyDSPConvolver, SGKeyDSPDDC,
             SGKeyDSPLiveprog, SGKeyDSPReverb, SGKeyDSPStereoWide, SGKeyDSPCrossfeed, SGKeyDSPTube];
}

NSString *SGDSPEffectOf(NSString *key) {
    for (NSString *effect in effectSwitches()) {
        if ([key isEqualToString:effect] || [key hasPrefix:[effect stringByAppendingString:@"."]]) return effect;
    }
    return SGKeyDSP;
}

SGDSPRange SGDSPRangeFor(NSString *key) {
    for (size_t i = 0; i < sizeof kNumbers / sizeof *kNumbers; i++) {
        if ([kNumbers[i].key isEqualToString:key]) return kNumbers[i].range;
    }
    return (SGDSPRange){0, 1, 0, 0};
}

#pragma mark - reading and writing

static NSUserDefaults *store(void) {
    return NSUserDefaults.standardUserDefaults;
}

BOOL SGDSPSwitch(NSString *key) {
    return SGHidden(key);
}

void SGDSPSetSwitch(NSString *key, BOOL on) {
    SGSetEnabled(key, on);
    SGDSPApply(SGDSPEffectOf(key));
}

double SGDSPNumber(NSString *key) {
    SGDSPRange range = SGDSPRangeFor(key);
    id value = [store() objectForKey:key];
    if (![value isKindOfClass:NSNumber.class]) return range.fallback;
    return MAX(range.min, MIN(range.max, [value doubleValue]));
}

void SGDSPSetNumber(NSString *key, double value) {
    SGDSPRange range = SGDSPRangeFor(key);
    [store() setDouble:MAX(range.min, MIN(range.max, value)) forKey:key];
    SGDSPApply(SGDSPEffectOf(key));
}

NSString *SGDSPString(NSString *key) {
    id value = [store() objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : (stringDefaults()[key] ?: @"");
}

void SGDSPSetString(NSString *key, NSString *value) {
    [store() setObject:value ?: @"" forKey:key];
    SGDSPApply(SGDSPEffectOf(key));
}

static NSUInteger gainCount(NSString *key) {
    return [key isEqualToString:SGKeyDSPCompanderGains] ? 7 : 15;
}

static double gainLimit(NSString *key) {
    return [key isEqualToString:SGKeyDSPCompanderGains] ? SGDSPCompanderGainLimit : SGDSPEqualizerGainLimit;
}

NSArray<NSNumber *> *SGDSPGains(NSString *key) {
    NSArray<NSString *> *parts = [SGDSPString(key) componentsSeparatedByString:@";"];
    NSUInteger count = gainCount(key);
    double limit = gainLimit(key);
    NSMutableArray<NSNumber *> *gains = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        double gain = i < parts.count ? parts[i].doubleValue : 0;
        [gains addObject:@(MAX(-limit, MIN(limit, gain)))];
    }
    return gains;
}

void SGDSPSetGains(NSString *key, NSArray<NSNumber *> *gains) {
    NSUInteger count = gainCount(key);
    double limit = gainLimit(key);
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        double gain = i < gains.count ? gains[i].doubleValue : 0;
        [parts addObject:[NSString stringWithFormat:@"%.2f", MAX(-limit, MIN(limit, gain))]];
    }
    SGDSPSetString(key, [parts componentsJoinedByString:@";"]);
}

void SGDSPResetAll(void) {
    for (size_t i = 0; i < sizeof kNumbers / sizeof *kNumbers; i++) [store() removeObjectForKey:kNumbers[i].key];
    for (NSString *key in stringDefaults()) [store() removeObjectForKey:key];
    for (NSString *effect in effectSwitches()) [store() removeObjectForKey:effect];
    SGDSPApply(SGKeyDSP);
    for (NSString *effect in effectSwitches()) SGDSPApply(effect);
}

#pragma mark - lists

NSArray<NSString *> *SGDSPEqualizerFilterNames(void) {
    return @[@"FIR minimum phase", @"IIR 4th order", @"IIR 6th order", @"IIR 8th order", @"IIR 10th order", @"IIR 12th order"];
}

NSArray<NSString *> *SGDSPEqualizerInterpolationNames(void) {
    return @[@"Cubic Hermite", @"Modified Akima"];
}

NSArray<NSString *> *SGDSPCompanderTransformNames(void) {
    return @[@"Uniform (short-time Fourier)", @"Multiresolution (continuous wavelet)",
             @"Pseudo multiresolution (undersampling)", @"Pseudo multiresolution (time domain)"];
}

NSArray<NSString *> *SGDSPConvolverModeNames(void) {
    return @[@"Original", @"Shrink", @"Minimum phase and shrink"];
}

NSArray<NSString *> *SGDSPCrossfeedModeNames(void) {
    return @[@"BS2B weak", @"BS2B strong", @"Out of head", @"Surround 1", @"Surround 2", @"Realistic surround"];
}

NSArray<NSString *> *SGDSPReverbPresetNames(void) {
    return @[@"Default", @"Small hall 1", @"Small hall 2", @"Medium hall", @"Large hall", @"Small room 1", @"Small room 2",
             @"Medium room", @"Large room", @"Plate high", @"Plate low", @"Long reverb 1", @"Long reverb 2"];
}

NSArray<NSString *> *SGDSPEqualizerPresetNames(void) {
    return @[@"Acoustic", @"Bass", @"Beats", @"Classic", @"Clear", @"Deep", @"Dubstep", @"Electronic", @"Flat",
             @"Hardstyle", @"Hip-Hop", @"Jazz", @"Metal", @"Movie", @"Pop", @"R&B", @"Rock", @"Vocal Booster"];
}

NSArray<NSNumber *> *SGDSPEqualizerPreset(NSInteger index) {
    static const double presets[][15] = {
        {5.00, 4.50, 4.00, 3.50, 1.50, 1.00, 1.50, 1.50, 2.00, 3.00, 3.50, 4.00, 3.70, 3.00, 3.00},
        {10.00, 8.80, 8.50, 6.50, 2.50, 1.50, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {-5.5, -5.0, -4.5, -4.2, -3.5, -3.0, -1.9, 0, 0, 0, 0, 0, 0, 0, 0},
        {-0.3, 0.3, -3.5, -9.0, -1.0, 0.0, 1.8, 2.1, 0.0, 0.0, 0.0, 4.4, 9.0, 9.0, 9.0},
        {3.5, 5.5, 6.5, 9.5, 8.0, 6.5, 3.5, 2.5, 1.3, 5.0, 7.0, 9.0, 10.0, 11.0, 9.0},
        {12.0, 8.0, 0.0, -6.7, -12.0, -9.0, -3.5, -3.5, -6.1, 0.0, -3.0, -5.0, 0.0, 1.2, 3.0},
        {12.0, 10.0, 0.5, -1.0, -3.0, -5.0, -5.0, -4.8, -4.5, -2.5, -1.0, 0.0, -2.5, -2.5, 0.0},
        {4.0, 4.0, 3.5, 1.0, 0.0, -0.5, -2.0, 0.0, 2.0, 0.0, 0.0, 1.0, 3.0, 4.0, 4.5},
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {6.1, 7.0, 12.0, 6.1, -5.0, -12.0, -2.5, 3.0, 6.5, 0.0, -2.2, -4.5, -6.1, -9.2, -10.0},
        {4.5, 4.3, 4.0, 2.5, 1.5, 3.0, -1.0, -1.5, -1.5, 1.5, 0.0, -1.0, 0.0, 1.5, 3.0},
        {0.0, 0.0, 0.0, 2.0, 4.0, 5.9, -5.9, -4.5, -2.5, 2.5, 1.0, -0.8, -0.8, -0.8, -0.8},
        {10.5, 10.5, 7.5, 0.0, 2.0, 5.5, 0.0, 0.0, 0.0, 6.1, 0.0, 0.0, 6.1, 10.0, 12.0},
        {3.0, 3.0, 6.1, 8.5, 9.0, 7.0, 6.1, 6.1, 5.0, 8.0, 3.5, 3.5, 8.0, 10.0, 8.0},
        {0.0, 0.0, 0.0, 0.0, 0.0, 1.3, 2.0, 2.5, 5.0, -1.5, -2.0, -3.0, -3.0, -3.0, -3.0},
        {3.0, 3.0, 7.0, 6.1, 4.5, 1.5, -1.5, -2.0, -1.5, 2.0, 2.5, 3.0, 3.5, 3.8, 4.0},
        {0.0, 0.0, 0.0, 3.0, 3.0, -10.0, -4.0, -1.0, 0.8, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0},
        {-1.5, -2.0, -3.0, -3.0, -0.5, 1.5, 3.5, 3.5, 3.5, 3.0, 2.0, 1.5, 0.0, 0.0, -1.5},
    };
    if (index < 0 || index >= (NSInteger)(sizeof presets / sizeof *presets)) return nil;
    NSMutableArray<NSNumber *> *gains = [NSMutableArray arrayWithCapacity:15];
    for (int i = 0; i < 15; i++) [gains addObject:@(presets[index][i])];
    return gains;
}
