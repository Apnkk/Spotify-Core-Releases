// Runs SGDSPEngine.m over the Mac build of libjamesdsp the way the tweak runs them: a song decoded with
// ExtAudioFile goes through the engine in slices of the sizes iOS hands its output unit (1024, 4096, 470 and
// 471 in turn, 512, and a mix), and each check prints a line.
//
// - bypass: every effect off, the output is the input one block later, sample for sample;
// - the same while another thread keeps changing settings, so blocks that pass dry keep the latency;
// - nothing allocated on the render thread, with every effect on;
// - no NaN, infinity or level over the limiter with every effect on;
// - bass boost lifts the lows, an equalizer preset moves each band by its gain;
// - every bundled Liveprog script compiles and runs, every DDC preset parses, a broken script names its line;
// - the convolver reproduces an impulse response (RootlessJamesDSP's Church.wav, 4 channels, 10 s);
// - a sample rate change, a reset and a restart;
// - what each effect costs per 1024-frame block.
//
//     ./build.sh && build/jamesdsp <song> <Church.wav> <out dir>
//     ./build.sh thread && build/jamesdsp-thread <song> <Church.wav> <out dir> stress     (and address)
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <malloc/malloc.h>
#import <pthread.h>
#import <stdatomic.h>
#import "Shared/JamesDSP/SGDSPEngine.h"
#include "JdspImpResToolbox.h"

static const double kRate = 48000;
static int sg_failures;

#define CHECK(ok, ...) do { bool _ok = (ok); if (!_ok) sg_failures++; printf("%s ", _ok ? "  ok  " : "FAILED"); printf(__VA_ARGS__); printf("\n"); } while (0)

#pragma mark - allocations on the render thread

// Defined in the executable, so the calls libjamesdsp and the engine make bind here rather than to libc's.
static _Thread_local bool sg_inRender;
static atomic_uint sg_renderAllocations;

#if !__has_feature(address_sanitizer) && !__has_feature(thread_sanitizer)
void *malloc(size_t size) {
    if (sg_inRender) atomic_fetch_add(&sg_renderAllocations, 1);
    return malloc_zone_malloc(malloc_default_zone(), size);
}

void *calloc(size_t count, size_t size) {
    if (sg_inRender) atomic_fetch_add(&sg_renderAllocations, 1);
    return malloc_zone_calloc(malloc_default_zone(), count, size);
}

void *realloc(void *pointer, size_t size) {
    if (sg_inRender) atomic_fetch_add(&sg_renderAllocations, 1);
    if (!pointer) return malloc_zone_malloc(malloc_default_zone(), size);
    malloc_zone_t *zone = malloc_zone_from_ptr(pointer);
    return malloc_zone_realloc(zone ?: malloc_default_zone(), pointer, size);
}
#define SG_COUNTS_ALLOCATIONS 1
#endif

#pragma mark - audio

typedef struct {
    float *left, *right;
    size_t frames;
} Audio;

static Audio makeAudio(size_t frames) {
    return (Audio){calloc(frames, sizeof(float)), calloc(frames, sizeof(float)), frames};
}

static Audio copyAudio(Audio audio) {
    Audio copy = makeAudio(audio.frames);
    memcpy(copy.left, audio.left, audio.frames * sizeof(float));
    memcpy(copy.right, audio.right, audio.frames * sizeof(float));
    return copy;
}

static void freeAudio(Audio audio) {
    free(audio.left);
    free(audio.right);
}

static void scaleAudio(Audio audio, float gain) {
    for (size_t i = 0; i < audio.frames; i++) {
        audio.left[i] *= gain;
        audio.right[i] *= gain;
    }
}

static AudioStreamBasicDescription floatFormat(double rate) {
    return (AudioStreamBasicDescription){
        .mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 32,
    };
}

static Audio decode(NSString *path, double rate, double seconds) {
    ExtAudioFileRef file;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &file)) {
        printf("cannot open %s\n", path.UTF8String);
        exit(1);
    }
    AudioStreamBasicDescription format = floatFormat(rate);
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    Audio audio = makeAudio((size_t)(rate * seconds));
    size_t done = 0;
    while (done < audio.frames) {
        UInt32 frames = (UInt32)MIN((size_t)8192, audio.frames - done);
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, frames * 4, audio.left + done}}}, {1, frames * 4, audio.right + done}};
        if (ExtAudioFileRead(file, &frames, &buffers.list) || !frames) break;
        done += frames;
    }
    ExtAudioFileDispose(file);
    audio.frames = done;
    return audio;
}

static void writeWav(NSString *path, Audio audio, double rate) {
    ExtAudioFileRef file;
    AudioStreamBasicDescription wav = {
        .mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 16,
    };
    if (ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], kAudioFileWAVEType, &wav, NULL, kAudioFileFlags_EraseFile, &file)) {
        printf("cannot write %s\n", path.UTF8String);
        return;
    }
    AudioStreamBasicDescription format = floatFormat(rate);
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    for (size_t done = 0; done < audio.frames;) {
        UInt32 frames = (UInt32)MIN((size_t)8192, audio.frames - done);
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, frames * 4, audio.left + done}}}, {1, frames * 4, audio.right + done}};
        ExtAudioFileWrite(file, frames, &buffers.list);
        done += frames;
    }
    ExtAudioFileDispose(file);
}

#pragma mark - running the engine

enum { kPattern1024, kPattern4096, kPatternOdd, kPattern512, kPatternMixed, kPatternCount };
static const char *kPatternNames[] = {"1024", "4096", "470/471", "512", "mixed"};

static uint32_t sliceAt(int pattern, size_t index) {
    static const uint32_t mixed[] = {1024, 4096, 470, 471, 512, 941, 1, 2048, 1023, 1025};
    switch (pattern) {
    case kPattern1024: return 1024;
    case kPattern4096: return 4096;
    case kPatternOdd: return index % 2 ? 471 : 470;
    case kPattern512: return 512;
    default: return mixed[index % 10];
    }
}

typedef struct {
    double meanMS, peakMS;
    uint64_t calls;
} Timing;

static double ticksToMS(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) mach_timebase_info(&timebase);
    return ticks * (double)timebase.numer / timebase.denom / 1e6;
}

// The audio processed in place through the engine, a slice at a time, as the notify does.
static Timing run(SGDSPEngine *engine, Audio audio, int pattern) {
    Timing timing = {0};
    uint64_t total = 0, peak = 0;
    size_t index = 0;
    for (size_t done = 0; done < audio.frames;) {
        uint32_t frames = (uint32_t)MIN((size_t)sliceAt(pattern, index++), audio.frames - done);
        uint64_t start = mach_absolute_time();
        sg_inRender = true;
        SGDSPEngineProcess(engine, audio.left + done, audio.right + done, frames);
        sg_inRender = false;
        uint64_t ticks = mach_absolute_time() - start;
        total += ticks;
        if (ticks > peak) peak = ticks;
        done += frames;
        timing.calls++;
    }
    timing.meanMS = ticksToMS(total) / timing.calls;
    timing.peakMS = ticksToMS(peak);
    return timing;
}

// How far the output is from the input one block earlier: samples that differ, and the largest difference.
static size_t delayedDifferences(Audio input, Audio output, float *largest) {
    size_t differ = 0;
    *largest = 0;
    for (size_t i = 0; i < output.frames; i++) {
        float wantLeft = i < kSGDSPEngineBlock ? 0 : input.left[i - kSGDSPEngineBlock];
        float wantRight = i < kSGDSPEngineBlock ? 0 : input.right[i - kSGDSPEngineBlock];
        float d = fmaxf(fabsf(output.left[i] - wantLeft), fabsf(output.right[i] - wantRight));
        if (output.left[i] != wantLeft || output.right[i] != wantRight) differ++;
        if (d > *largest) *largest = d;
    }
    return differ;
}

static bool finiteAndBounded(Audio audio, float bound, float *peak) {
    *peak = 0;
    for (size_t i = 0; i < audio.frames; i++) {
        if (!isfinite(audio.left[i]) || !isfinite(audio.right[i])) return false;
        *peak = fmaxf(*peak, fmaxf(fabsf(audio.left[i]), fabsf(audio.right[i])));
    }
    return *peak <= bound;
}

static void discardLine(const char *text, void *context) {
}

static void drainLog(void) {
    SGDSPEngineReadLog(discardLine, NULL, 1000);
}

static void printLine(const char *text, void *context) {
    int *count = context;
    if ((*count)++ < 12) printf("         jamesdsp: %s%s", text, text[strlen(text) - 1] == '\n' ? "" : "\n");
}

#pragma mark - settings

static const double kEqFrequencies[15] = {25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000};
static const double kCompanderFrequencies[7] = {95, 200, 400, 800, 1600, 3400, 7500};
// JamesDSP's Bass and Vocal Booster presets (SGDSPEqualizerPreset).
static const double kPresetBass[15] = {10.00, 8.80, 8.50, 6.50, 2.50, 1.50, 0, 0, 0, 0, 0, 0, 0, 0, 0};
static const double kPresetVocal[15] = {-1.5, -2.0, -3.0, -3.0, -0.5, 1.5, 3.5, 3.5, 3.5, 3.0, 2.0, 1.5, 0.0, 0.0, -1.5};

static const void *bundled(const char *wantKind, const char *wantName) {
    const char *kind, *name;
    const void *data;
    for (unsigned i = 0; SGDSPEngineBundledFile(i, &kind, &name, &data, NULL); i++) {
        if (!strcmp(kind, wantKind) && !strcmp(name, wantName)) return data;
    }
    return NULL;
}

static void allOff(SGDSPEngine *engine) {
    char error[300];
    double zeros[15] = {0};
    SGDSPEngineSetOutput(engine, 0, -0.1, 60);
    SGDSPEngineSetCompander(engine, false, 0.22, 2, 0, kCompanderFrequencies, zeros);
    SGDSPEngineSetBassBoost(engine, false, 5);
    SGDSPEngineSetEqualizer(engine, false, 0, 0, kEqFrequencies, zeros);
    SGDSPEngineSetGraphicEq(engine, false, "GraphicEQ: 0.0 0.0;", error, sizeof error);
    SGDSPEngineSetConvolver(engine, false, NULL, 0, NULL, error, sizeof error);
    SGDSPEngineSetDDC(engine, false, NULL, error, sizeof error);
    SGDSPEngineSetLiveprog(engine, false, NULL, error, sizeof error);
    SGDSPEngineSetReverb(engine, false, 15);
    SGDSPEngineSetStereoWide(engine, false, 60);
    SGDSPEngineSetCrossfeed(engine, false, 5);
    SGDSPEngineSetTube(engine, false, 2);
}

typedef enum {
    kCompander, kBass, kEqFIR, kEqIIR, kGraphicEq, kConvolver, kDDC, kLiveprog, kLiveprogHeavy, kReverb, kWide,
    kCrossfeedBS2B, kCrossfeedSurround, kTube, kEffectCount
} Effect;

static const char *kEffectNames[] = {
    "compander (STFT)", "bass boost 5 dB", "equalizer FIR", "equalizer IIR 8th", "graphic EQ", "convolver Church.wav",
    "DDC Butterworth", "Liveprog stereowide", "Liveprog DRX10K compander", "reverb plate high", "stereo wide 60%",
    "crossfeed BS2B weak", "crossfeed realistic surround", "tube 2 dB",
};

static NSString *sg_church;

static bool setEffect(SGDSPEngine *engine, Effect effect, bool on) {
    char error[300] = "";
    static const double companderGains[7] = {0.3, 0.2, 0, -0.1, 0.1, 0.3, 0.4};
    bool ok = true;
    switch (effect) {
    case kCompander: SGDSPEngineSetCompander(engine, on, 0.22, 2, 0, kCompanderFrequencies, companderGains); break;
    case kBass: SGDSPEngineSetBassBoost(engine, on, 5); break;
    case kEqFIR: SGDSPEngineSetEqualizer(engine, on, 0, 0, kEqFrequencies, kPresetVocal); break;
    case kEqIIR: SGDSPEngineSetEqualizer(engine, on, 3, 0, kEqFrequencies, kPresetVocal); break;
    case kGraphicEq:
        ok = SGDSPEngineSetGraphicEq(engine, on, "GraphicEQ: 20 4; 60 3; 200 0; 1000 -1; 3000 2; 8000 1; 16000 -3; 20000 -6", error, sizeof error);
        break;
    case kConvolver: ok = SGDSPEngineSetConvolver(engine, on, sg_church.UTF8String, 0, "-80;-100;0;0;0;0", error, sizeof error); break;
    case kDDC: ok = SGDSPEngineSetDDC(engine, on, bundled("DDC", "Butterworth.vdc"), error, sizeof error); break;
    case kLiveprog: ok = SGDSPEngineSetLiveprog(engine, on, bundled("Liveprog", "stereowide.eel"), error, sizeof error); break;
    case kLiveprogHeavy:
        ok = SGDSPEngineSetLiveprog(engine, on, bundled("Liveprog", "Joe0Bloggs DRX10K compander-HR.eel"), error, sizeof error);
        break;
    case kReverb: SGDSPEngineSetReverb(engine, on, 15); break;
    case kWide: SGDSPEngineSetStereoWide(engine, on, 60); break;
    case kCrossfeedBS2B: SGDSPEngineSetCrossfeed(engine, on, 0); break;
    case kCrossfeedSurround: SGDSPEngineSetCrossfeed(engine, on, 5); break;
    case kTube: SGDSPEngineSetTube(engine, on, 2); break;
    default: break;
    }
    if (!ok) printf("         %s: %s\n", kEffectNames[effect], error);
    return ok;
}

static void allOn(SGDSPEngine *engine) {
    for (Effect e = 0; e < kEffectCount; e++) {
        if (e == kEqFIR || e == kLiveprogHeavy || e == kCrossfeedBS2B) continue;   // one of each
        setEffect(engine, e, true);
    }
}

#pragma mark - measuring

// A band's level: two cascaded RBJ biquads (low pass, high pass or band), then RMS, in dB.
typedef struct { double b0, b1, b2, a1, a2, x1, x2, y1, y2; } Biquad;

static Biquad biquad(int kind, double frequency, double rate) {
    double w = 2 * M_PI * frequency / rate, cw = cos(w), alpha = sin(w) / (2 * M_SQRT1_2);
    double b0, b1, b2, a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
    if (kind == 0) { b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2; }
    else { b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2; }
    return (Biquad){b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}

static double bandLevel(Audio audio, size_t from, int kind, double frequency) {
    Biquad filters[2] = {biquad(kind, frequency, kRate), biquad(kind, frequency, kRate)};
    double sum = 0;
    for (size_t i = 0; i < audio.frames; i++) {
        double x = 0.5 * (audio.left[i] + audio.right[i]);
        for (int f = 0; f < 2; f++) {
            Biquad *q = &filters[f];
            double y = q->b0 * x + q->b1 * q->x1 + q->b2 * q->x2 - q->a1 * q->y1 - q->a2 * q->y2;
            q->x2 = q->x1; q->x1 = x; q->y2 = q->y1; q->y1 = y;
            x = y;
        }
        if (i >= from) sum += x * x;
    }
    return 10 * log10(sum / (audio.frames - from) + 1e-30);
}

// A tone's amplitude by a Hann-windowed DFT at its frequency.
static double toneLevel(const float *samples, size_t count, double frequency) {
    double re = 0, im = 0, window = 0;
    for (size_t i = 0; i < count; i++) {
        double w = 0.5 - 0.5 * cos(2 * M_PI * i / (count - 1));
        double phase = 2 * M_PI * frequency * i / kRate;
        re += samples[i] * w * cos(phase);
        im += samples[i] * w * sin(phase);
        window += w;
    }
    return 20 * log10(2 * hypot(re, im) / window);
}

#pragma mark - the checks

static void checkBypass(Audio song) {
    printf("\nbypass: every effect off, the output is the input one block later\n");
    for (int pattern = 0; pattern < kPatternCount; pattern++) {
        SGDSPEngine *engine = SGDSPEngineCreate(kRate);
        allOff(engine);
        Audio quiet = copyAudio(song);
        scaleAudio(quiet, 0.5f);   // under the limiter's -0.1 dB
        Audio output = copyAudio(quiet);
        run(engine, output, pattern);
        float largest;
        size_t differ = delayedDifferences(quiet, output, &largest);
        CHECK(differ == 0, "slices of %-8s at -6 dB: %zu of %zu samples differ from the input 1024 frames earlier", kPatternNames[pattern], differ, output.frames * 2);
        freeAudio(output);
        freeAudio(quiet);

        // At full level the limiter at -0.1 dB takes the song's peaks, and only those.
        SGDSPEngineRestart(engine);
        output = copyAudio(song);
        run(engine, output, pattern);
        differ = delayedDifferences(song, output, &largest);
        size_t over = 0;
        for (size_t i = 0; i < song.frames; i++) over += fabsf(song.left[i]) > 0.98855f || fabsf(song.right[i]) > 0.98855f;
        if (pattern == kPattern1024) {
            printf("         at full level: %zu samples (%.3f%%) differ, the largest by %.4f, where the song has %zu samples over the limiter's %.4f\n",
                   differ, 100.0 * differ / (output.frames * 2), largest, over, 0.98855);
        }
        freeAudio(output);
        SGDSPEngineFree(engine);
    }
}

static void checkRestart(Audio song) {
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    Audio quiet = copyAudio(song);
    quiet.frames = (size_t)kRate * 4;
    scaleAudio(quiet, 0.5f);
    Audio first = copyAudio(quiet);
    run(engine, first, kPatternOdd);
    SGDSPEngineRestart(engine);
    Audio second = copyAudio(quiet);
    run(engine, second, kPatternOdd);
    float largest;
    size_t differ = delayedDifferences(quiet, second, &largest);
    CHECK(differ == 0, "after a restart the stream starts over one block late (%zu samples differ)", differ);
    freeAudio(first);
    freeAudio(second);
    freeAudio(quiet);
    SGDSPEngineFree(engine);
}

static void checkAllOn(Audio song, NSString *outDir) {
    printf("\nevery effect on\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    allOn(engine);
    drainLog();
    Audio output = copyAudio(song);
    atomic_store(&sg_renderAllocations, 0);
    Timing timing = run(engine, output, kPatternMixed);
    float peak = 0;
    bool fine = finiteAndBounded(output, 0.98856f, &peak);
    CHECK(fine, "no NaN or infinity and nothing over the limiter's threshold: peak %.4f (%.2f dBFS)", peak, 20 * log10(peak));
    SGDSPEngineStats stats = SGDSPEngineReadStats(engine, true);
    CHECK(stats.faults == 0, "no block silenced as not finite (%llu of %llu)", stats.faults, stats.blocks);
#if SG_COUNTS_ALLOCATIONS
    unsigned allocations = atomic_load(&sg_renderAllocations);
    CHECK(allocations == 0, "no allocation on the render thread over %llu calls in mixed slices (%u)", timing.calls, allocations);
#endif
    writeWav([outDir stringByAppendingPathComponent:@"all-on.wav"], output, kRate);
    freeAudio(output);
    SGDSPEngineFree(engine);
    (void)timing;
}

static void checkBass(Audio song, NSString *outDir) {
    printf("\nbass boost and the equalizer\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    SGDSPEngineSetOutput(engine, -6, -0.1, 60);   // headroom, so the limiter does not take the boost back
    Audio reference = copyAudio(song);
    run(engine, reference, kPattern1024);
    SGDSPEngineSetBassBoost(engine, true, 5);
    SGDSPEngineRestart(engine);
    Audio boosted = copyAudio(song);
    run(engine, boosted, kPattern1024);
    size_t skip = (size_t)kRate;
    double lowBefore = bandLevel(reference, skip, 0, 100), lowAfter = bandLevel(boosted, skip, 0, 100);
    double highBefore = bandLevel(reference, skip, 1, 2000), highAfter = bandLevel(boosted, skip, 1, 2000);
    CHECK(lowAfter - lowBefore > 2, "bass boost 5 dB: under 100 Hz %+.1f dB, over 2 kHz %+.1f dB", lowAfter - lowBefore, highAfter - highBefore);
    writeWav([outDir stringByAppendingPathComponent:@"bass-5dB.wav"], boosted, kRate);
    freeAudio(boosted);
    SGDSPEngineSetBassBoost(engine, false, 5);

    // The Bass preset on the song: lows up, the rest as it was.
    SGDSPEngineSetEqualizer(engine, true, 0, 0, kEqFrequencies, kPresetBass);
    SGDSPEngineRestart(engine);
    Audio bass = copyAudio(song);
    run(engine, bass, kPattern1024);
    lowAfter = bandLevel(bass, skip, 0, 60);
    lowBefore = bandLevel(reference, skip, 0, 60);
    highAfter = bandLevel(bass, skip, 1, 2000);
    highBefore = bandLevel(reference, skip, 1, 2000);
    CHECK(lowAfter - lowBefore > 5 && fabs(highAfter - highBefore) < 1, "EQ preset Bass on the song: under 60 Hz %+.1f dB, over 2 kHz %+.1f dB",
          lowAfter - lowBefore, highAfter - highBefore);
    writeWav([outDir stringByAppendingPathComponent:@"eq-bass-preset.wav"], bass, kRate);
    freeAudio(bass);
    freeAudio(reference);

    // Tones at the fifteen bands, each moved by its gain: Vocal Booster, FIR and IIR.
    size_t frames = (size_t)kRate * 6;
    Audio tones = makeAudio(frames);
    for (size_t i = 0; i < frames; i++) {
        double sum = 0;
        for (int b = 0; b < 15; b++) sum += 0.02 * sin(2 * M_PI * kEqFrequencies[b] * i / kRate + b);
        tones.left[i] = tones.right[i] = (float)sum;
    }
    SGDSPEngineSetOutput(engine, 0, -0.1, 60);
    for (int filter = 0; filter <= 3; filter += 3) {
        SGDSPEngineSetEqualizer(engine, true, filter, 0, kEqFrequencies, kPresetVocal);
        SGDSPEngineRestart(engine);
        Audio out = copyAudio(tones);
        run(engine, out, kPatternOdd);
        double worst = 0;
        char line[512] = "";
        size_t from = (size_t)kRate * 2 + kSGDSPEngineBlock, count = (size_t)kRate * 3;
        for (int b = 0; b < 15; b++) {
            double gain = toneLevel(out.left + from, count, kEqFrequencies[b]) - toneLevel(tones.left + from - kSGDSPEngineBlock, count, kEqFrequencies[b]);
            worst = fmax(worst, fabs(gain - kPresetVocal[b]));
            snprintf(line + strlen(line), sizeof line - strlen(line), " %+.1f", gain);
        }
        CHECK(worst < 1.5, "Vocal Booster, %s: each band's tone off its gain by %.2f dB at most; measured%s", filter ? "IIR 8th order" : "FIR", worst, line);
        freeAudio(out);
    }
    freeAudio(tones);
    SGDSPEngineFree(engine);
}

static void checkLiveprogAndDDC(Audio song) {
    printf("\nbundled files\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    Audio clip = copyAudio(song);
    clip.frames = (size_t)kRate;
    const char *kind, *name;
    const void *data;
    size_t length;
    unsigned scripts = 0, compiled = 0, presets = 0, parsed = 0, scriptsAllocating = 0;
    char error[300];
    for (unsigned i = 0; SGDSPEngineBundledFile(i, &kind, &name, &data, &length); i++) {
        bool isScript = !strcmp(kind, "Liveprog");
        uint64_t start = mach_absolute_time();
        bool ok = isScript ? SGDSPEngineSetLiveprog(engine, true, data, error, sizeof error) : SGDSPEngineSetDDC(engine, true, data, error, sizeof error);
        double ms = ticksToMS(mach_absolute_time() - start);
        Audio out = copyAudio(clip);
        unsigned allocationsBefore = atomic_load(&sg_renderAllocations);
        Timing timing = run(engine, out, kPattern1024);
        unsigned allocations = atomic_load(&sg_renderAllocations) - allocationsBefore;
        scriptsAllocating += allocations > 0;
        float peak = 0;
        bool fine = finiteAndBounded(out, 0.98856f, &peak);
        if (isScript) scripts++, compiled += ok && fine;
        else presets++, parsed += ok && fine;
        if (!ok || !fine) printf("FAILED %s %s: %s%s\n", kind, name, ok ? "" : error, fine ? "" : " (output not finite)");
        else printf("         %-8s %-40s %6zu bytes, set in %7.1f ms, %.3f ms a block%s\n", kind, name, length, ms, timing.meanMS,
                    allocations ? [NSString stringWithFormat:@", %u allocations while processing", allocations].UTF8String : "");
        freeAudio(out);
        if (isScript) SGDSPEngineSetLiveprog(engine, false, NULL, error, sizeof error);
        else SGDSPEngineSetDDC(engine, false, NULL, error, sizeof error);
    }
    CHECK(compiled == scripts && scripts == 40, "%u of %u bundled Liveprog scripts compile and run finite", compiled, scripts);
    CHECK(parsed == presets && presets == 3, "%u of %u bundled DDC presets parse and run finite", parsed, presets);
#if SG_COUNTS_ALLOCATIONS
    printf("         %u of them allocate while processing (EEL gives a script memory the first time it touches it)\n", scriptsAllocating);
#endif

    // A broken script names the line of the file, in either section.
    const char *brokenInit = "desc: broken\n// a comment\n@init\nx = 1;\ny = (2 + ;\n@sample\nspl0 = spl0;\n";
    bool ok = SGDSPEngineSetLiveprog(engine, true, brokenInit, error, sizeof error);
    CHECK(!ok && !strncmp(error, "Line 5:", 7), "a script broken in @init at line 5: \"%s\"", error);
    const char *brokenSample = "desc: broken\n@init\nx = 1;\n@sample\nspl0 = spl0;\nspl1 = spl1 * ;\n";
    ok = SGDSPEngineSetLiveprog(engine, true, brokenSample, error, sizeof error);
    CHECK(!ok && !strncmp(error, "Line 6:", 7), "a script broken in @sample at line 6: \"%s\"", error);
    ok = SGDSPEngineSetLiveprog(engine, true, "desc: none\nspl0 = 0;\n", error, sizeof error);
    CHECK(!ok, "a script without sections: \"%s\"", error);
    ok = SGDSPEngineSetDDC(engine, true, "SR_44100:1,2,3\nSR_48000:1,2,3,", error, sizeof error);
    CHECK(!ok, "a malformed DDC file is refused before libjamesdsp's parser: \"%s\"", error);
    ok = SGDSPEngineSetGraphicEq(engine, true, "GraphicEQ: 20 -1; 30", error, sizeof error);
    CHECK(ok, "a GraphicEQ with an odd count of numbers loads its whole pairs");
    ok = SGDSPEngineSetGraphicEq(engine, true, "20 -1; 30 2", error, sizeof error);
    CHECK(!ok, "text without \"GraphicEQ:\" is refused: \"%s\"", error);

    // Liveprog's printf comes out through the log.
    int lines = 0;
    SGDSPEngineReadLog(printLine, &lines, 1000);
    lines = 0;
    SGDSPEngineSetLiveprog(engine, true, "desc: talk\n@init\nprintf(\"hello from @init %d\", 42);\n@sample\nspl0 = spl0;\n", error, sizeof error);
    SGDSPEngineReadLog(printLine, &lines, 1000);
    CHECK(lines > 0, "Liveprog's printf reaches the engine's log (%d line)", lines);
    freeAudio(clip);
    SGDSPEngineFree(engine);
}

static void writeMonoWav(NSString *from, NSString *to) {
    ExtAudioFileRef in, out;
    ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:from], &in);
    AudioStreamBasicDescription mono = {48000, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked, 4, 1, 4, 1, 32, 0};
    AudioStreamBasicDescription four = {48000, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked, 16, 1, 16, 4, 32, 0};
    ExtAudioFileSetProperty(in, kExtAudioFileProperty_ClientDataFormat, sizeof four, &four);
    ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:to], kAudioFileWAVEType, &mono, NULL, kAudioFileFlags_EraseFile, &out);
    float frame[4 * 4096], left[4096];
    for (;;) {
        UInt32 frames = 4096;
        AudioBufferList list = {1, {{4, sizeof frame, frame}}};
        if (ExtAudioFileRead(in, &frames, &list) || !frames) break;
        for (UInt32 i = 0; i < frames; i++) left[i] = frame[i * 4];
        AudioBufferList outList = {1, {{1, frames * 4, left}}};
        ExtAudioFileWrite(out, frames, &outList);
    }
    ExtAudioFileDispose(in);
    ExtAudioFileDispose(out);
}

static void checkConvolver(Audio song, NSString *outDir) {
    printf("\nconvolver\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    char error[300];
    uint64_t start = mach_absolute_time();
    bool ok = SGDSPEngineSetConvolver(engine, true, sg_church.UTF8String, 0, "-80;-100;0;0;0;0", error, sizeof error);
    CHECK(ok, "Church.wav loads (%.0f ms)%s%s", ticksToMS(mach_absolute_time() - start), ok ? "" : ": ", ok ? "" : error);

    // An impulse in the left channel comes out as the response's LL and LR channels, one block later.
    int info[2], wave[6] = {-80, -100, 0, 0, 0, 0};
    float *ir = ReadImpulseResponseToFloat(sg_church.UTF8String, 48000, info, 0, wave);
    size_t frames = (size_t)info[1] + 8192;
    Audio impulse = makeAudio(frames);
    impulse.left[100] = 0.5f;
    Audio out = copyAudio(impulse);
    SGDSPEngineSetOutput(engine, 0, 0, 60);
    run(engine, out, kPatternMixed);
    double error2 = 0, energy = 0;
    for (int i = 0; i < info[1] && 100 + kSGDSPEngineBlock + (size_t)i < frames; i++) {
        size_t at = 100 + kSGDSPEngineBlock + i;
        float wantLeft = 0.5f * ir[i * info[0] + 0], wantRight = 0.5f * ir[i * info[0] + 1];
        error2 += (out.left[at] - wantLeft) * (out.left[at] - wantLeft) + (out.right[at] - wantRight) * (out.right[at] - wantRight);
        energy += wantLeft * wantLeft + wantRight * wantRight;
    }
    CHECK(10 * log10(error2 / energy) < -60, "an impulse comes out as the response (%d channels, %d frames): error %.0f dB under it", info[0], info[1], 10 * log10(error2 / energy));
    free(ir);
    freeAudio(out);
    freeAudio(impulse);

    // On the song, and its cost.
    SGDSPEngineSetOutput(engine, -6, -0.1, 60);
    Audio wet = copyAudio(song);
    wet.frames = MIN(wet.frames, (size_t)kRate * 30);
    SGDSPEngineRestart(engine);
    Timing timing = run(engine, wet, kPattern1024);
    float peak = 0;
    CHECK(finiteAndBounded(wet, 0.98856f, &peak), "Church.wav on the song: %.3f ms a block on average, %.3f ms at most", timing.meanMS, timing.peakMS);
    writeWav([outDir stringByAppendingPathComponent:@"convolver-church.wav"], wet, kRate);
    freeAudio(wet);

    // Shrink, and minimum phase on a mono response (the case the reader wrote out of bounds in).
    ok = SGDSPEngineSetConvolver(engine, true, sg_church.UTF8String, 1, "-80;-100;0;0;0;0", error, sizeof error);
    CHECK(ok, "shrink mode loads");
    NSString *mono = [outDir stringByAppendingPathComponent:@"church-mono.wav"];
    writeMonoWav(sg_church, mono);
    ok = SGDSPEngineSetConvolver(engine, true, mono.UTF8String, 2, "-80;-100;0;0;0;0", error, sizeof error);
    CHECK(ok, "minimum phase and shrink loads a mono response");
    ok = SGDSPEngineSetConvolver(engine, true, mono.UTF8String, 0, "-80;-100;999999999;0;0;0", error, sizeof error);
    CHECK(ok, "a waveform shift past the response falls back to the defaults");
    ok = SGDSPEngineSetConvolver(engine, true, "/nonexistent.wav", 0, NULL, error, sizeof error);
    CHECK(!ok, "a missing file: \"%s\"", error);
    ok = SGDSPEngineSetConvolver(engine, true, [outDir stringByAppendingPathComponent:@"all-on.wav"].UTF8String, 0, NULL, error, sizeof error);
    CHECK(ok, "a 16-bit stereo WAV reads as a response too");
    SGDSPEngineFree(engine);
}

static void checkRateAndReset(Audio song) {
    printf("\nsample rate change and reset\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    allOn(engine);
    Audio a = copyAudio(song);
    a.frames = (size_t)kRate * 3;
    run(engine, a, kPattern1024);
    SGDSPEngineSetSampleRate(engine, 44100);
    allOn(engine);
    Audio b = copyAudio(song);
    b.frames = 44100 * 3;
    run(engine, b, kPattern4096);
    float peak = 0;
    CHECK(SGDSPEngineSampleRate(engine) == 44100 && finiteAndBounded(b, 0.98856f, &peak), "48 -> 44.1 kHz with every effect on: runs finite, peak %.3f", peak);
    SGDSPEngineSetSampleRate(engine, 96000);
    allOn(engine);
    Audio c = copyAudio(song);
    c.frames = 96000 * 2;
    run(engine, c, kPatternOdd);
    CHECK(finiteAndBounded(c, 0.98856f, &peak), "-> 96 kHz (libjamesdsp resamples to 48 inside): runs finite, peak %.3f", peak);
    SGDSPEngineSetSampleRate(engine, kRate);
    SGDSPEngineReset(engine);
    allOff(engine);
    SGDSPEngineRestart(engine);
    Audio quiet = copyAudio(song);
    quiet.frames = (size_t)kRate * 3;
    scaleAudio(quiet, 0.5f);
    Audio out = copyAudio(quiet);
    run(engine, out, kPatternMixed);
    float largest;
    size_t differ = delayedDifferences(quiet, out, &largest);
    CHECK(differ == 0, "after a reset every effect is off and the output is the input one block later (%zu differ)", differ);
    freeAudio(a);
    freeAudio(b);
    freeAudio(c);
    freeAudio(quiet);
    freeAudio(out);
    SGDSPEngineFree(engine);
}

static void checkCost(Audio song) {
    printf("\ncost per 1024-frame block at 48 kHz (21.33 ms of sound), 20 s of the song\n");
    SGDSPEngine *engine = SGDSPEngineCreate(kRate);
    allOff(engine);
    Audio clip = copyAudio(song);
    clip.frames = MIN(clip.frames, (size_t)kRate * 20);
    double blockMS = kSGDSPEngineBlock / kRate * 1000;
    for (int e = -1; e <= kEffectCount; e++) {
        const char *name = e < 0 ? "every effect off" : e == kEffectCount ? "every effect on" : kEffectNames[e];
        if (e == kEffectCount) allOn(engine);
        else if (e >= 0) setEffect(engine, (Effect)e, true);
        Audio out = copyAudio(clip);
        Timing timing = run(engine, out, kPattern1024);
        printf("         %-30s %7.3f ms  (%5.2f%% of real time), peak %7.3f ms\n", name, timing.meanMS, timing.meanMS / blockMS * 100, timing.peakMS);
        freeAudio(out);
        if (e >= 0 && e < kEffectCount) setEffect(engine, (Effect)e, false);
    }
    freeAudio(clip);
    SGDSPEngineFree(engine);
}

#pragma mark - stress

typedef struct {
    SGDSPEngine *engine;
    atomic_bool stop;
    unsigned changes;
    bool effectsOn;
    useconds_t pause;                     // between changes; the apply queue waits 30 ms for a burst to end
    double longestMS[kEffectCount + 1];   // the longest a setter took, per effect and the output's
} Hammer;

static void *hammer(void *context) {
    Hammer *h = context;
    char error[300];
    double zeros[15] = {0};
    unsigned i = 0;
    while (!atomic_load(&h->stop)) {
        if (!h->effectsOn) {
            // Setters that leave the sound as it is, so every block, processed or passed dry, must be exact.
            switch (i % 6) {
            case 0: SGDSPEngineSetOutput(h->engine, 0, -0.1, 60); break;
            case 1: SGDSPEngineSetReverb(h->engine, false, 15); break;
            case 2: SGDSPEngineSetEqualizer(h->engine, false, 0, 0, kEqFrequencies, zeros); break;
            case 3: SGDSPEngineSetCrossfeed(h->engine, false, 5); break;
            case 4: SGDSPEngineSetLiveprog(h->engine, false, NULL, error, sizeof error); break;
            case 5: SGDSPEngineSetDDC(h->engine, false, NULL, error, sizeof error); break;
            }
        } else {
            // Every effect in turn, on and off, the output now and then; as fast as the setters go.
            Effect e = (Effect)(i % kEffectCount);
            uint64_t start = mach_absolute_time();
            setEffect(h->engine, e, (i / kEffectCount) % 2 == 0);
            h->longestMS[e] = fmax(h->longestMS[e], ticksToMS(mach_absolute_time() - start));
            if (i % 7 == 0) {
                start = mach_absolute_time();
                SGDSPEngineSetOutput(h->engine, (i % 7) - 3.0, -0.1 - (i % 5), 30 + i % 100);
                h->longestMS[kEffectCount] = fmax(h->longestMS[kEffectCount], ticksToMS(mach_absolute_time() - start));
            }
        }
        i++;
        h->changes++;
        drainLog();
        if (h->pause) usleep(h->pause);
    }
    return NULL;
}

// The song through the engine in mixed slices, at `speed` times real time, while a hammer runs; the longest
// stretch of blocks passed dry.
static unsigned runPaced(Hammer *h, Audio out, double speed) {
    pthread_t thread;
    pthread_create(&thread, NULL, hammer, h);
    uint64_t began = mach_absolute_time(), lastDry = 0, lastBlocks = 0;
    unsigned streak = 0, longest = 0;
    size_t index = 0;
    for (size_t done = 0; done < out.frames;) {
        uint32_t frames = (uint32_t)MIN((size_t)sliceAt(kPatternMixed, index++), out.frames - done);
        SGDSPEngineProcess(h->engine, out.left + done, out.right + done, frames);
        done += frames;
        SGDSPEngineStats now = SGDSPEngineReadStats(h->engine, false);
        if (now.dry != lastDry && now.blocks == lastBlocks) streak += (unsigned)(now.dry - lastDry);
        else if (now.blocks != lastBlocks) streak = now.dry != lastDry ? 1 : 0;
        longest = MAX(longest, streak);
        lastDry = now.dry;
        lastBlocks = now.blocks;
        if (speed > 0) {
            double due = done / kRate / speed * 1000, elapsed = ticksToMS(mach_absolute_time() - began);
            if (due > elapsed) usleep((useconds_t)((due - elapsed) * 1000));
        }
    }
    atomic_store(&h->stop, true);
    pthread_join(thread, NULL);
    return longest;
}

static void checkStress(Audio song, bool quick) {
    printf("\na thread changing settings while another processes\n");
    // As fast as it goes, with settings that leave the sound alone: blocks passed dry must keep the latency.
    Hammer h = {.engine = SGDSPEngineCreate(kRate)};
    allOff(h.engine);
    Audio quiet = copyAudio(song);
    quiet.frames = MIN(quiet.frames, (size_t)kRate * (quick ? 8 : 40));
    scaleAudio(quiet, 0.5f);
    Audio out = copyAudio(quiet);
    pthread_t thread;
    pthread_create(&thread, NULL, hammer, &h);
    run(h.engine, out, kPatternMixed);
    atomic_store(&h.stop, true);
    pthread_join(thread, NULL);
    SGDSPEngineStats stats = SGDSPEngineReadStats(h.engine, true);
    float largest = 0, peak = 0;
    size_t differ = delayedDifferences(quiet, out, &largest);
    CHECK(differ == 0 && stats.dry > 0, "settings that leave the sound alone, %u changes: %llu blocks processed, %llu passed dry, %zu samples off the input one block earlier",
          h.changes, stats.blocks, stats.dry, differ);
    freeAudio(out);
    SGDSPEngineFree(h.engine);

    // Every effect switched on and off as fast as the setters go, the song unpaced: no crash, nothing not
    // finite.
    Hammer e = {.engine = SGDSPEngineCreate(kRate), .effectsOn = true};
    allOff(e.engine);
    out = copyAudio(quiet);
    runPaced(&e, out, 0);
    stats = SGDSPEngineReadStats(e.engine, true);
    CHECK(finiteAndBounded(out, 0.98856f, &peak) && stats.faults == 0, "every effect switched on and off as fast as it goes, %u changes: %llu blocks processed, %llu dry, output finite, peak %.3f",
          e.changes, stats.blocks, stats.dry, peak);
    freeAudio(out);
    SGDSPEngineFree(e.engine);

    // The same at the pace the apply queue can go (a change every 30 ms at most) and the song in real time:
    // how long a change leaves the sound dry.
    Hammer p = {.engine = SGDSPEngineCreate(kRate), .effectsOn = true, .pause = 30000};
    allOff(p.engine);
    out = copyAudio(quiet);
    out.frames = MIN(out.frames, (size_t)kRate * (quick ? 4 : 10));
    unsigned longest = runPaced(&p, out, 1);
    stats = SGDSPEngineReadStats(p.engine, true);
    CHECK(finiteAndBounded(out, 0.98856f, &peak) && stats.faults == 0,
          "a change every 30 ms in real time, %u changes: %llu blocks processed, %llu dry (%.1f%%), the longest dry stretch %u blocks (%.0f ms), peak %.3f",
          p.changes, stats.blocks, stats.dry, 100.0 * stats.dry / (stats.blocks + stats.dry), longest, longest * kSGDSPEngineBlock / kRate * 1000, peak);
    printf("         the longest each setter held on:");
    for (int i = 0; i <= kEffectCount; i++) printf("%s %s %.1f ms", i ? "," : "", i < kEffectCount ? kEffectNames[i] : "output", p.longestMS[i]);
    printf("\n");
    freeAudio(out);
    freeAudio(quiet);
    SGDSPEngineFree(p.engine);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        if (argc < 4) {
            printf("usage: %s <song> <Church.wav> <out dir> [stress]\n", argv[0]);
            return 2;
        }
        NSString *songPath = @(argv[1]);
        sg_church = @(argv[2]);
        NSString *outDir = @(argv[3]);
        bool stressOnly = argc > 4 && !strcmp(argv[4], "stress");
        [NSFileManager.defaultManager createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];
        Audio song = decode(songPath, kRate, stressOnly ? 12 : 60);
        printf("song: %.1f s at %.0f Hz\n", song.frames / kRate, kRate);
        if (stressOnly) {
            checkStress(song, true);
            checkRateAndReset(song);
        } else {
            checkBypass(song);
            checkRestart(song);
            checkAllOn(song, outDir);
            checkBass(song, outDir);
            checkLiveprogAndDDC(song);
            checkConvolver(song, outDir);
            checkRateAndReset(song);
            checkStress(song, false);
            checkCost(song);
            Audio original = copyAudio(song);
            original.frames = MIN(original.frames, (size_t)kRate * 30);
            writeWav([outDir stringByAppendingPathComponent:@"original.wav"], original, kRate);
            SGDSPEngine *engine = SGDSPEngineCreate(kRate);
            allOff(engine);
            SGDSPEngineSetReverb(engine, true, 15);
            SGDSPEngineSetOutput(engine, -3, -0.1, 60);
            Audio reverb = copyAudio(original);
            run(engine, reverb, kPattern1024);
            writeWav([outDir stringByAppendingPathComponent:@"reverb-plate-high.wav"], reverb, kRate);
            SGDSPEngineFree(engine);
        }
        printf("\n%s: %d failed\n", sg_failures ? "FAILED" : "all passed", sg_failures);
        return sg_failures ? 1 : 0;
    }
}
