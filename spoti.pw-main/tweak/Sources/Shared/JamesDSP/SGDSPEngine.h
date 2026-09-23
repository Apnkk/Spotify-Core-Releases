// JamesDSP's engine, libjamesdsp (vendor/libjamesdsp), made fit for Core Audio's render thread: one per
// process, fed the finished output a slice at a time, whatever size the slice.
//
// libjamesdsp wants a fixed block: every change of the frame count reallocates its buffers and rebuilds
// its convolutions (pfloat32 -> JamesDSPRefreshConvolutions), and iOS hands the output unit 1024 frames,
// 4096 with the screen locked, sometimes an odd count. So the engine re-blocks: frames go into a block of
// kSGDSPEngineBlock, a full block is processed, and the processed frames come out of a FIFO primed with one
// block of silence. The sound is always exactly one block later than it went in (21 ms at 48 kHz),
// whatever the slices.
//
// libjamesdsp's setters are mostly not safe against processing, so every setter here takes the engine's
// lock, and the render thread only tries it: a block that finds it taken passes through unprocessed, one
// block late all the same, so nothing jumps while a setting changes.
//
// Threading: SGDSPEngineProcess runs on the render thread and never allocates, blocks, logs or messages
// (libjamesdsp takes a mutex of its own around three effects there, which only this lock's holder can
// hold, so it never waits). SGDSPEngineRestart and the diagnostics are for any thread. Everything else is
// the config side: one thread at a time, never the render thread. Plain C; compiles on the Mac as is
// (harness/jamesdsp).
#import <stdbool.h>
#import <stddef.h>
#import <stdint.h>

enum { kSGDSPEngineBlock = 1024 };

typedef struct SGDSPEngine SGDSPEngine;

// Stereo at `sampleRate`, every effect off, output gain 0 dB. NULL when libjamesdsp could not start.
SGDSPEngine *SGDSPEngineCreate(double sampleRate);
// Only once nothing renders through it.
void SGDSPEngineFree(SGDSPEngine *engine);

// Any thread.
double SGDSPEngineSampleRate(const SGDSPEngine *engine);
// A new rate, every effect rebuilt for it by libjamesdsp; the file effects (convolver, DDC, Liveprog) and
// the ones it does not refresh itself (reverb, tube, the IIR equalizer) are set again by the caller.
void SGDSPEngineSetSampleRate(SGDSPEngine *engine, double sampleRate);
// libjamesdsp started over, every effect off, for when its output stopped being finite.
void SGDSPEngineReset(SGDSPEngine *engine);

#pragma mark - effects, the config side

void SGDSPEngineSetOutput(SGDSPEngine *engine, double postGainDB, double limiterThresholdDB, double limiterReleaseMS);
void SGDSPEngineSetCompander(SGDSPEngine *engine, bool on, double timeConstant, int granularity, int transform,
                             const double frequencies[7], const double gains[7]);
void SGDSPEngineSetBassBoost(SGDSPEngine *engine, bool on, double maxGainDB);
// filter: 0 FIR minimum phase, 1...5 IIR of order 4, 6, 8, 10, 12. interpolation: 0 cubic Hermite, 1 Akima.
void SGDSPEngineSetEqualizer(SGDSPEngine *engine, bool on, int filter, int interpolation, const double frequencies[15],
                             const double gains[15]);
// preset: libjamesdsp's own number (sf_reverb_preset), not a list index.
void SGDSPEngineSetReverb(SGDSPEngine *engine, bool on, int preset);
void SGDSPEngineSetStereoWide(SGDSPEngine *engine, bool on, double levelPercent);
// mode: 0 BS2B weak, 1 BS2B strong, 2 out of head, 3 surround 1, 4 surround 2, 5 realistic surround.
void SGDSPEngineSetCrossfeed(SGDSPEngine *engine, bool on, int mode);
void SGDSPEngineSetTube(SGDSPEngine *engine, bool on, double driveDB);

// These answer false and say why in `error` when the effect could not take; it is then off.
// AutoEq's GraphicEQ format, "GraphicEQ: 20 -1.2; 21 -1.1; ...".
bool SGDSPEngineSetGraphicEq(SGDSPEngine *engine, bool on, const char *nodes, char *error, size_t errorSize);
// An impulse response file (.wav, .irs, .flac) read at the engine's rate. mode: 0 original, 1 shrink, 2
// minimum phase and shrink. waveEdit: JamesDSP's advanced waveform editing, "-80;-100;0;0;0;0".
bool SGDSPEngineSetConvolver(SGDSPEngine *engine, bool on, const char *path, int mode, const char *waveEdit,
                             char *error, size_t errorSize);
// A ViPER DDC file's text.
bool SGDSPEngineSetDDC(SGDSPEngine *engine, bool on, const char *text, char *error, size_t errorSize);
// A Liveprog script's text; a compile error names the file's line.
bool SGDSPEngineSetLiveprog(SGDSPEngine *engine, bool on, const char *script, char *error, size_t errorSize);

#pragma mark - the render thread

// Replaces `frames` samples of each lane with the processed sound one block before them.
void SGDSPEngineProcess(SGDSPEngine *engine, float *left, float *right, uint32_t frames);
// The next SGDSPEngineProcess starts over from a block of silence, for a stream that stopped and starts
// again (the sound held from before it would otherwise play first). Any thread.
void SGDSPEngineRestart(SGDSPEngine *engine);

#pragma mark - diagnostics, any thread

typedef struct {
    uint64_t blocks;        // processed
    uint64_t dry;           // passed through because a setting was being changed
    uint64_t faults;        // came out not finite and were silenced
    double averageMS;       // processing time of a block, a running average
    double peakMS;          // the longest since the peak was last taken
    double load;            // averageMS over the block's duration
} SGDSPEngineStats;

// takePeak starts the peak over; one reader takes it, the others leave it.
SGDSPEngineStats SGDSPEngineReadStats(SGDSPEngine *engine, bool takePeak);

// What libjamesdsp printed (printf, its Android log, Liveprog's printf), a line at a time, oldest first, at
// most `max` of them; answers how many were dropped because the lines came faster than they were read. The
// lines are kept by the engine's handlers, which any thread (the render thread too) may call.
unsigned SGDSPEngineReadLog(void (*line)(const char *text, void *context), void *context, unsigned max);

#pragma mark - curves and files, any thread but not at once

// `count` points log-spaced from 20 Hz to 20 kHz into `frequencies`, and the curve at them.
void SGDSPEngineEqualizerCurve(int filter, int interpolation, const double bandFrequencies[15], const double gains[15],
                               int count, double *frequencies, double *decibels);
void SGDSPEngineCompanderCurve(const double bandFrequencies[7], const double gains[7], int count, double *frequencies,
                               double *values);

// The files RootlessJamesDSP ships with the engine (vendor/libjamesdsp/assets), compiled in: kind is
// "Liveprog" or "DDC". false past the last.
bool SGDSPEngineBundledFile(unsigned index, const char **kind, const char **name, const void **data, size_t *length);
