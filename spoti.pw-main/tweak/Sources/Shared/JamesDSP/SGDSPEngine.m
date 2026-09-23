// SGDSPEngine.h says what this is. The effect setters follow RootlessJamesDSP's JamesDspWrapper.cpp call for
// call, with its fixes where it had a bug (noted where they are).
#import "SGDSPEngine.h"
#import <mach/mach_time.h>
#import <math.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
// vendor/libjamesdsp, on the include path of this file alone (tweak/Makefile).
#include "jdsp_header.h"
#include "JdspImpResToolbox.h"
#include "EELStdOutExtension.h"
#include "PrintfStdOutExtension.h"
#include "JdspBundledFiles.h"

// The FIFO the processed blocks wait in: a power of two holding the primed block, the one being handed out
// and the one just made, with room to spare.
enum { kRing = 4 * kSGDSPEngineBlock };

struct SGDSPEngine {
    JamesDSPLib *dsp;
    pthread_mutex_t lock;             // held by every setter, tried by the render thread
    atomic_uint_fast64_t rateBits;
    atomic_bool restart;

    // The render thread's alone.
    uint32_t fill;                    // frames in the block being gathered
    uint64_t written, read;           // frames into and out of the ring, the written ones a block ahead
    float blockLeft[kSGDSPEngineBlock], blockRight[kSGDSPEngineBlock];
    float ringLeft[kRing], ringRight[kRing];

    atomic_uint_fast64_t blocks, dry, faults;
    atomic_uint_fast64_t averageBits, peakNanos;
};

static double sg_nanosPerTick;

static void storeDouble(atomic_uint_fast64_t *slot, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store_explicit(slot, bits, memory_order_relaxed);
}

static double loadDouble(const atomic_uint_fast64_t *slot) {
    uint64_t bits = atomic_load_explicit((atomic_uint_fast64_t *)slot, memory_order_relaxed);
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static void copyError(char *error, size_t errorSize, const char *text) {
    if (error && errorSize) snprintf(error, errorSize, "%s", text);
}

#pragma mark - what libjamesdsp prints

// A ring of lines any thread may add to, the render thread included (Liveprog's printf runs inside the
// processing), and one reader takes from: claimed by a compare and swap, published by a flag.
enum { kLogSlots = 64, kLogBytes = 200 };

typedef struct {
    atomic_uint ready;
    char text[kLogBytes];
} LogSlot;

static LogSlot sg_log[kLogSlots];
static atomic_uint sg_logHead, sg_logTail, sg_logDropped;

static void keepLine(const char *text, void *context) {
    if (!text || !*text) return;
    unsigned head = atomic_load_explicit(&sg_logHead, memory_order_relaxed);
    do {
        if (head - atomic_load_explicit(&sg_logTail, memory_order_acquire) >= kLogSlots) {
            atomic_fetch_add_explicit(&sg_logDropped, 1, memory_order_relaxed);
            return;
        }
    } while (!atomic_compare_exchange_weak_explicit(&sg_logHead, &head, head + 1, memory_order_acq_rel, memory_order_relaxed));
    LogSlot *slot = &sg_log[head % kLogSlots];
    size_t length = strnlen(text, kLogBytes - 1);
    memcpy(slot->text, text, length);
    slot->text[length] = 0;
    atomic_store_explicit(&slot->ready, 1, memory_order_release);
}

unsigned SGDSPEngineReadLog(void (*line)(const char *text, void *context), void *context, unsigned max) {
    for (unsigned done = 0; done < max; done++) {
        unsigned tail = atomic_load_explicit(&sg_logTail, memory_order_relaxed);
        LogSlot *slot = &sg_log[tail % kLogSlots];
        if (!atomic_load_explicit(&slot->ready, memory_order_acquire)) break;
        char text[kLogBytes];
        memcpy(text, slot->text, sizeof text);
        atomic_store_explicit(&slot->ready, 0, memory_order_relaxed);
        atomic_store_explicit(&sg_logTail, tail + 1, memory_order_release);
        line(text, context);
    }
    return atomic_exchange_explicit(&sg_logDropped, 0, memory_order_relaxed);
}

#pragma mark - making one

// EEL's global tables and the handlers are the process's, set up once.
static void startLibrary(void) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    sg_nanosPerTick = (double)timebase.numer / timebase.denom;
    JamesDSPGlobalMemoryAllocation();
    setStdOutHandler(keepLine, NULL);
    setPrintfStdOutHandler(keepLine, NULL);
}

static bool validRate(double rate) {
    return rate >= 8000 && rate <= 384000;
}

// The FIFO back to one block of silence ahead of the first frame in.
static void startOver(SGDSPEngine *engine) {
    engine->fill = 0;
    engine->read = 0;
    engine->written = kSGDSPEngineBlock;
    memset(engine->ringLeft, 0, kSGDSPEngineBlock * sizeof(float));
    memset(engine->ringRight, 0, kSGDSPEngineBlock * sizeof(float));
}

SGDSPEngine *SGDSPEngineCreate(double sampleRate) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    if (!validRate(sampleRate)) return NULL;
    pthread_once(&once, startLibrary);
    SGDSPEngine *engine = calloc(1, sizeof *engine);
    JamesDSPLib *dsp = calloc(1, sizeof *dsp);
    if (!engine || !dsp || pthread_mutex_init(&engine->lock, NULL) != 0) {
        free(engine);
        free(dsp);
        return NULL;
    }
    JamesDSPInit(dsp, kSGDSPEngineBlock, (float)sampleRate);
    if (!JamesDSPGetMutexStatus(dsp)) {
        JamesDSPFree(dsp);
        free(dsp);
        pthread_mutex_destroy(&engine->lock);
        free(engine);
        return NULL;
    }
    engine->dsp = dsp;
    storeDouble(&engine->rateBits, sampleRate);
    startOver(engine);
    return engine;
}

void SGDSPEngineFree(SGDSPEngine *engine) {
    if (!engine) return;
    pthread_mutex_lock(&engine->lock);
    JamesDSPFree(engine->dsp);
    free(engine->dsp);
    pthread_mutex_unlock(&engine->lock);
    pthread_mutex_destroy(&engine->lock);
    free(engine);
}

double SGDSPEngineSampleRate(const SGDSPEngine *engine) {
    return loadDouble(&engine->rateBits);
}

void SGDSPEngineSetSampleRate(SGDSPEngine *engine, double sampleRate) {
    if (!validRate(sampleRate) || sampleRate == SGDSPEngineSampleRate(engine)) return;
    pthread_mutex_lock(&engine->lock);
    JamesDSPSetSampleRate(engine->dsp, (float)sampleRate, 1);
    storeDouble(&engine->rateBits, sampleRate);
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineReset(SGDSPEngine *engine) {
    pthread_mutex_lock(&engine->lock);
    JamesDSPFree(engine->dsp);
    JamesDSPInit(engine->dsp, kSGDSPEngineBlock, (float)SGDSPEngineSampleRate(engine));
    pthread_mutex_unlock(&engine->lock);
}

#pragma mark - the render thread

static bool allFinite(const float *left, const float *right) {
    // Anything times zero is zero, but for NaN and infinity: the sum is NaN when one of them is.
    float sum = 0;
    for (uint32_t i = 0; i < kSGDSPEngineBlock; i++) sum += left[i] * 0.0f + right[i] * 0.0f;
    return sum == sum;
}

// The gathered block, processed (or as it is, when a setter holds the lock) into the ring. The ring is a
// whole number of blocks and blocks are written whole, so a block never wraps.
static void runBlock(SGDSPEngine *engine) {
    uint64_t at = engine->written & (kRing - 1);
    float *left = engine->ringLeft + at, *right = engine->ringRight + at;
    if (pthread_mutex_trylock(&engine->lock) != 0) {
        memcpy(left, engine->blockLeft, sizeof engine->blockLeft);
        memcpy(right, engine->blockRight, sizeof engine->blockRight);
        atomic_fetch_add_explicit(&engine->dry, 1, memory_order_relaxed);
    } else {
        uint64_t start = mach_absolute_time();
        JamesDSPLib *dsp = engine->dsp;
        dsp->processFloatDeinterleaved(dsp, engine->blockLeft, engine->blockRight, left, right, kSGDSPEngineBlock);
        pthread_mutex_unlock(&engine->lock);
        uint64_t nanos = (uint64_t)((mach_absolute_time() - start) * sg_nanosPerTick);
        double average = loadDouble(&engine->averageBits);
        storeDouble(&engine->averageBits, average ? average + (nanos - average) * 0.05 : nanos);
        if (nanos > atomic_load_explicit(&engine->peakNanos, memory_order_relaxed)) {
            atomic_store_explicit(&engine->peakNanos, nanos, memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&engine->blocks, 1, memory_order_relaxed);
        // An effect gone unstable would put NaN into its own state and every block after; silence rather
        // than noise, and the config side resets the engine when it sees the count move.
        if (!allFinite(left, right)) {
            memset(left, 0, sizeof engine->blockLeft);
            memset(right, 0, sizeof engine->blockRight);
            atomic_fetch_add_explicit(&engine->faults, 1, memory_order_relaxed);
        }
    }
    engine->written += kSGDSPEngineBlock;
}

void SGDSPEngineProcess(SGDSPEngine *engine, float *left, float *right, uint32_t frames) {
    if (atomic_exchange_explicit(&engine->restart, false, memory_order_acquire)) startOver(engine);
    uint32_t in = 0, out = 0;
    while (in < frames) {
        uint32_t take = kSGDSPEngineBlock - engine->fill;
        if (take > frames - in) take = frames - in;
        memcpy(engine->blockLeft + engine->fill, left + in, take * sizeof(float));
        memcpy(engine->blockRight + engine->fill, right + in, take * sizeof(float));
        engine->fill += take;
        in += take;
        if (engine->fill == kSGDSPEngineBlock) {
            runBlock(engine);
            engine->fill = 0;
        }
        // As many frames out as came in: the ring is always a block ahead, so it has them, and the frames
        // overwritten were copied into the block already.
        while (out < in) {
            uint32_t at = (uint32_t)(engine->read & (kRing - 1));
            uint32_t count = in - out;
            if (count > kRing - at) count = kRing - at;
            memcpy(left + out, engine->ringLeft + at, count * sizeof(float));
            memcpy(right + out, engine->ringRight + at, count * sizeof(float));
            engine->read += count;
            out += count;
        }
    }
}

void SGDSPEngineRestart(SGDSPEngine *engine) {
    atomic_store_explicit(&engine->restart, true, memory_order_release);
}

SGDSPEngineStats SGDSPEngineReadStats(SGDSPEngine *engine, bool takePeak) {
    SGDSPEngineStats stats = {
        .blocks = atomic_load_explicit(&engine->blocks, memory_order_relaxed),
        .dry = atomic_load_explicit(&engine->dry, memory_order_relaxed),
        .faults = atomic_load_explicit(&engine->faults, memory_order_relaxed),
        .averageMS = loadDouble(&engine->averageBits) / 1e6,
        .peakMS = (takePeak ? atomic_exchange_explicit(&engine->peakNanos, 0, memory_order_relaxed)
                            : atomic_load_explicit(&engine->peakNanos, memory_order_relaxed)) / 1e6,
    };
    double blockMS = kSGDSPEngineBlock / SGDSPEngineSampleRate(engine) * 1000;
    stats.load = stats.averageMS / blockMS;
    return stats;
}

#pragma mark - effects

void SGDSPEngineSetOutput(SGDSPEngine *engine, double postGainDB, double limiterThresholdDB, double limiterReleaseMS) {
    pthread_mutex_lock(&engine->lock);
    JamesDSPSetPostGain(engine->dsp, postGainDB);
    JLimiterSetCoefficients(engine->dsp, limiterThresholdDB, limiterReleaseMS);
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetCompander(SGDSPEngine *engine, bool on, double timeConstant, int granularity, int transform,
                             const double frequencies[7], const double gains[7]) {
    pthread_mutex_lock(&engine->lock);
    if (on) {
        double freq[7], gain[7];
        memcpy(freq, frequencies, sizeof freq);
        memcpy(gain, gains, sizeof gain);
        CompressorSetParam(engine->dsp, (float)timeConstant, granularity, transform, 0);
        CompressorSetGain(engine->dsp, freq, gain, 1);
        CompressorEnable(engine->dsp, 1);
    } else {
        CompressorDisable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetBassBoost(SGDSPEngine *engine, bool on, double maxGainDB) {
    pthread_mutex_lock(&engine->lock);
    if (on) {
        BassBoostSetParam(engine->dsp, (float)maxGainDB);
        BassBoostEnable(engine->dsp);
    } else {
        BassBoostDisable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetEqualizer(SGDSPEngine *engine, bool on, int filter, int interpolation, const double frequencies[15],
                             const double gains[15]) {
    pthread_mutex_lock(&engine->lock);
    if (on) {
        double freq[15], gain[15];
        memcpy(freq, frequencies, sizeof freq);
        memcpy(gain, gains, sizeof gain);
        MultimodalEqualizerAxisInterpolation(engine->dsp, interpolation, filter, freq, gain);
        MultimodalEqualizerEnable(engine->dsp, 1);
    } else {
        MultimodalEqualizerDisable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetReverb(SGDSPEngine *engine, bool on, int preset) {
    pthread_mutex_lock(&engine->lock);
    if (on) {
        // The preset first: it sets up the reverb's state for the rate, which enabling does not.
        Reverb_SetParam(engine->dsp, preset);
        ReverbEnable(engine->dsp);
    } else {
        ReverbDisable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetStereoWide(SGDSPEngine *engine, bool on, double levelPercent) {
    pthread_mutex_lock(&engine->lock);
    StereoEnhancementDisable(engine->dsp);
    StereoEnhancementSetParam(engine->dsp, (float)(levelPercent / 100));
    if (on) StereoEnhancementEnable(engine->dsp);
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetCrossfeed(SGDSPEngine *engine, bool on, int mode) {
    pthread_mutex_lock(&engine->lock);
    // CrossfeedChangeMode alone leaves BS2B weak's filter zeroed (JDSP4Linux's "audio loss"); enabling
    // after it sets both BS2B filters up, so it is always followed by CrossfeedEnable while on.
    CrossfeedChangeMode(engine->dsp, mode);
    if (on) CrossfeedEnable(engine->dsp, 1);
    else CrossfeedDisable(engine->dsp);
    pthread_mutex_unlock(&engine->lock);
}

void SGDSPEngineSetTube(SGDSPEngine *engine, bool on, double driveDB) {
    pthread_mutex_lock(&engine->lock);
    if (on) {
        // Enabling sets the tube up anew with its gain at 0 dB, so the drive goes in after, in dB, which the
        // library clamps to -3...12 (RootlessJamesDSP sets it first, and divided by 100).
        VacuumTubeEnable(engine->dsp);
        VacuumTubeSetGain(engine->dsp, driveDB);
    } else {
        VacuumTubeDisable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
}

#pragma mark - effects that read something

// "GraphicEQ: f g; f g; ..." rewritten from the pairs found in it, so libjamesdsp's parser, which writes
// past its nodes on an odd count of numbers, only ever sees whole pairs. NULL when there are none.
static char *graphicEqNodes(const char *text) {
    const char *p = strchr(text, ':');
    if (!p) return NULL;
    p++;
    size_t capacity = 64, length = 0;
    char *result = malloc(capacity);
    if (!result) return NULL;
    length = (size_t)snprintf(result, capacity, "GraphicEQ:");
    unsigned pairs = 0;
    while (*p) {
        char *end;
        double frequency = strtod(p, &end);
        if (end == p) {
            p++;
            continue;
        }
        p = end;
        while (*p == ' ' || *p == '\t') p++;
        double gain = strtod(p, &end);
        if (end == p) break;
        p = end;
        if (!isfinite(frequency) || !isfinite(gain) || frequency < 0) continue;
        char pair[64];
        int written = snprintf(pair, sizeof pair, " %.6g %.6g;", frequency, gain);
        if (length + written + 1 > capacity) {
            capacity = (length + written + 1) * 2;
            char *grown = realloc(result, capacity);
            if (!grown) {
                free(result);
                return NULL;
            }
            result = grown;
        }
        memcpy(result + length, pair, written + 1);
        length += written;
        pairs++;
    }
    if (!pairs) {
        free(result);
        return NULL;
    }
    return result;
}

bool SGDSPEngineSetGraphicEq(SGDSPEngine *engine, bool on, const char *nodes, char *error, size_t errorSize) {
    char *canonical = on && nodes && strstr(nodes, "GraphicEQ:") ? graphicEqNodes(nodes) : NULL;
    pthread_mutex_lock(&engine->lock);
    if (canonical) {
        ArbitraryResponseEqualizerStringParser(engine->dsp, canonical);
        ArbitraryResponseEqualizerEnable(engine->dsp, 1);
    } else {
        ArbitraryResponseEqualizerDisable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
    free(canonical);
    if (on && !canonical) {
        copyError(error, errorSize, "Not in AutoEq's GraphicEQ format (\"GraphicEQ: 20 -1.2; 21 -1.1; ...\")");
        return false;
    }
    return true;
}

bool SGDSPEngineSetConvolver(SGDSPEngine *engine, bool on, const char *path, int mode, const char *waveEdit,
                             char *error, size_t errorSize) {
    if (!on || !path || !*path) {
        pthread_mutex_lock(&engine->lock);
        Convolver1DDisable(engine->dsp);
        pthread_mutex_unlock(&engine->lock);
        return true;
    }
    // JamesDSP's defaults unless the setting is six whole numbers; the reader checks the shifts fit.
    int wave[6] = {-80, -100, 0, 0, 0, 0}, parsed[6];
    if (waveEdit && sscanf(waveEdit, "%d;%d;%d;%d;%d;%d", &parsed[0], &parsed[1], &parsed[2], &parsed[3], &parsed[4], &parsed[5]) == 6) {
        memcpy(wave, parsed, sizeof wave);
    }
    if (mode < 0 || mode > 2) mode = 0;
    // Read and resampled outside the lock: the render thread keeps processing meanwhile. At the rate the
    // effects run at, which is the output's but for rates libjamesdsp resamples to 44.1 or 48 kHz.
    int info[2] = {0, 0};
    float *impulse = ReadImpulseResponseToFloat(path, (int)engine->dsp->fs, info, mode, wave);
    int result = 0;
    pthread_mutex_lock(&engine->lock);
    Convolver1DDisable(engine->dsp);
    if (impulse && info[1] > 0) {
        result = Convolver1DLoadImpulseResponse(engine->dsp, impulse, (unsigned)info[0], (size_t)info[1], 1);
        if (result > 0) Convolver1DEnable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
    free(impulse);
    if (!impulse) {
        copyError(error, errorSize, "The impulse response could not be read: a WAV or FLAC file of 1, 2 or 4 channels");
        return false;
    }
    if (info[1] <= 0 || result <= 0) {
        copyError(error, errorSize, info[1] <= 0 ? "The impulse response is empty" : "The impulse response could not be loaded");
        return false;
    }
    return true;
}

// Whether libjamesdsp's DDC parser can read the text without running off its end or past its filters:
// both rates' sections, as many numbers after each as the 48 kHz section has fields, five to a filter.
static bool readableDDC(const char *text) {
    const char *at441 = strstr(text, "SR_44100"), *at48 = strstr(text, "SR_48000");
    if (!at441 || !at48 || strlen(text) > (1 << 20)) return false;
    unsigned fields = 1;
    for (const char *p = at48; *p; p++) fields += *p == ',';
    if (fields < 5 || fields % 5) return false;
    const char *starts[2] = {at441 + 9, at48 + 9};
    for (int s = 0; s < 2; s++) {
        if (starts[s] > text + strlen(text)) return false;
        unsigned numbers = 0;
        for (const char *p = starts[s]; *p && numbers < fields;) {
            char *end;
            strtod(p, &end);
            if (end != p) {
                numbers++;
                p = end;
            } else {
                p++;
            }
        }
        if (numbers < fields) return false;
    }
    return true;
}

bool SGDSPEngineSetDDC(SGDSPEngine *engine, bool on, const char *text, char *error, size_t errorSize) {
    bool readable = on && text && readableDDC(text);
    pthread_mutex_lock(&engine->lock);
    bool loaded = false;
    if (readable) {
        int parsed = DDCStringParser(engine->dsp, (char *)text);
        loaded = parsed >= 0 && DDCEnable(engine->dsp, 1) > 0;
    }
    if (!loaded) DDCDisable(engine->dsp);
    pthread_mutex_unlock(&engine->lock);
    if (on && !loaded) {
        copyError(error, errorSize, "Not a ViPER DDC file (SR_44100 and SR_48000 filters)");
        return false;
    }
    return true;
}

// The line of the file a section's line is: libjamesdsp compiles @init and @sample apart, each numbered from
// its own start, which is the line after its marker.
static int fileLine(const char *script, const char *marker, int sectionLine) {
    const char *at = strstr(script, marker);
    if (!at) return sectionLine;
    int line = 1;
    for (const char *p = script; p < at; p++) line += *p == '\n';
    return line + sectionLine;
}

bool SGDSPEngineSetLiveprog(SGDSPEngine *engine, bool on, const char *script, char *error, size_t errorSize) {
    pthread_mutex_lock(&engine->lock);
    LiveProgDisable(engine->dsp);
    if (!on || !script || !*script) {
        pthread_mutex_unlock(&engine->lock);
        return true;
    }
    // Compiled and its @init run under the lock: libjamesdsp takes its own processing mutex for all of it,
    // which the render thread would otherwise wait on.
    int result = LiveProgStringParser(engine->dsp, (char *)script);
    const char *compileError = NSEEL_code_getcodeerror(engine->dsp->eel.vm);
    char message[300] = "";
    if (result <= 0) {
        // -1 and -3 are a section that did not compile, whose error EEL kept; 0 and -2 a section missing.
        int line = 0, used = 0;
        bool compiled = result == -1 || result == -3;
        if (compiled && compileError && sscanf(compileError, "%d:%n", &line, &used) == 1 && used > 0) {
            const char *marker = result == -1 ? "@init" : "@sample";
            snprintf(message, sizeof message, "Line %d: %s", fileLine(script, marker, line), compileError + used + (compileError[used] == ' '));
        } else if (compiled && compileError) {
            snprintf(message, sizeof message, "%s: %s", checkErrorCode(result), compileError);
        } else {
            snprintf(message, sizeof message, "%s", checkErrorCode(result));
        }
    } else {
        LiveProgEnable(engine->dsp);
    }
    pthread_mutex_unlock(&engine->lock);
    if (result <= 0) {
        copyError(error, errorSize, message);
        return false;
    }
    return true;
}

#pragma mark - curves

static void logSpaced(int count, double *frequencies) {
    for (int i = 0; i < count; i++) {
        frequencies[i] = count > 1 ? 20 * pow(1000, (double)i / (count - 1)) : 1000;
    }
}

void SGDSPEngineEqualizerCurve(int filter, int interpolation, const double bandFrequencies[15], const double gains[15],
                               int count, double *frequencies, double *decibels) {
    if (count <= 0) return;
    logSpaced(count, frequencies);
    double gain[15];
    memcpy(gain, gains, sizeof gain);
    if (filter <= 0) {
        // The FIR equalizer's curve is its gains interpolated, as JamesDSP draws it.
        float *response = malloc(count * sizeof(float));
        if (!response) return;
        ComputeEqResponse(bandFrequencies, gain, interpolation, count, frequencies, response);
        for (int i = 0; i < count; i++) decibels[i] = response[i];
        free(response);
        return;
    }
    static const int orders[] = {4, 6, 8, 10, 12};
    int order = orders[filter > 5 ? 4 : filter - 1];
    double *re = malloc(count * sizeof(double)), *im = malloc(count * sizeof(double));
    if (re && im) {
        ComputeIIREqualizerCplx(48000, order, bandFrequencies, gain, count, frequencies, re, im);
        for (int i = 0; i < count; i++) decibels[i] = 20 * log10(fmax(hypot(re[i], im[i]), 1e-12));
    }
    free(re);
    free(im);
}

void SGDSPEngineCompanderCurve(const double bandFrequencies[7], const double gains[7], int count, double *frequencies,
                               double *values) {
    if (count <= 0) return;
    logSpaced(count, frequencies);
    float *response = malloc(count * sizeof(float));
    if (!response) return;
    ComputeCompResponse(7, bandFrequencies, gains, count, frequencies, response);
    for (int i = 0; i < count; i++) values[i] = response[i];
    free(response);
}

#pragma mark - bundled files

bool SGDSPEngineBundledFile(unsigned index, const char **kind, const char **name, const void **data, size_t *length) {
    if (index >= jdspBundledFileCount) return false;
    const JdspBundledFile *file = &jdspBundledFiles[index];
    if (kind) *kind = file->kind;
    if (name) *name = file->name;
    if (data) *data = file->data;
    if (length) *length = file->length;
    return true;
}
