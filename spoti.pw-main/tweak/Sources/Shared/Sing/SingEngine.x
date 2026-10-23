#import <AudioToolbox/AudioToolbox.h>
#import <CoreMotion/CoreMotion.h>
#import <math.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Core/SGRebind.h"
#import "Sing.h"

// Real-time Vocal Stem Separation & 3D Head-Tracked Spatial Voice DSP Engine.
// Operates in-place on Spotify's RemoteIO AudioUnit post-render callback without requiring external downloads.

enum {
    kSGSingMaxDelaySamples = 128,
    kSGSingRoomDelayL = 1103,
    kSGSingRoomDelayR = 1361,
};

static atomic_bool sg_singFeatureOn = true;
static atomic_bool sg_singSessionActive = false;
static atomic_bool sg_singLightMode = false;
static atomic_int sg_singVocalLevelBits = 0; // float bits, default 0.10f (karaoke vocal reduction)

static atomic_bool sg_spatialOn = false;
static atomic_int sg_spatialDistance = 35;   // 0..100
static atomic_int sg_spatialRoom = 30;       // 0..100
static atomic_int sg_spatialBack = 1;        // 0=Off, 1=Slow, 2=Medium, 3=Fast
static atomic_int sg_spatialWidth = 115;     // 50..150

static atomic_int sg_relYawBits = 0;         // float bits in radians (-pi..pi)
static atomic_int sg_vocalPeakBits = 0;
static atomic_int sg_instPeakBits = 0;

static inline void storeFloat(atomic_int *slot, float val) {
    int32_t bits;
    memcpy(&bits, &val, sizeof(bits));
    atomic_store_explicit(slot, bits, memory_order_relaxed);
}

static inline float loadFloat(atomic_int *slot) {
    int32_t bits = atomic_load_explicit(slot, memory_order_relaxed);
    float val;
    memcpy(&val, &bits, sizeof(val));
    return val;
}

BOOL SGSingEnabled(void) {
    return SGFlag(SGKeySing, YES);
}

BOOL SGSingActive(void) {
    return atomic_load_explicit(&sg_singSessionActive, memory_order_relaxed);
}

void SGSetSingActive(BOOL active) {
    atomic_store_explicit(&sg_singSessionActive, active, memory_order_relaxed);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SGSingStateDidChangeNotification" object:nil];
}

float SGSingVocalLevel(void) {
    NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:SGKeySingVocalLevel];
    return num ? fmaxf(0.0f, fminf(1.0f, num.floatValue)) : 0.15f;
}

void SGSetSingVocalLevel(float level) {
    level = fmaxf(0.0f, fminf(1.0f, level));
    [NSUserDefaults.standardUserDefaults setFloat:level forKey:SGKeySingVocalLevel];
    storeFloat(&sg_singVocalLevelBits, level);
}

BOOL SGSpatialVoiceEnabled(void) {
    return SGFlag(SGKeySpatialVoice, NO);
}

float SGSpatialVoiceRelativeYaw(void) {
    return loadFloat(&sg_relYawBits);
}

float SGSingLiveVocalPeak(void) {
    return loadFloat(&sg_vocalPeakBits);
}

float SGSingLiveInstrumentPeak(void) {
    return loadFloat(&sg_instPeakBits);
}

NSString *SGSingSummary(void) {
    if (!SGSingEnabled()) return @"Off";
    return SGSingActive() ? @"Active" : @"On";
}

NSString *SGSpatialVoiceSummary(void) {
    return SGSpatialVoiceEnabled() ? @"On" : @"Off";
}

#pragma mark - Headphone Motion Tracking (AirPods Pro / Max / 3rd Gen / Beats)

@interface SGSpatialMotionTracker : NSObject <CMHeadphoneMotionManagerDelegate>
+ (instancetype)shared;
- (void)syncState;
@end

@implementation SGSpatialMotionTracker {
    CMHeadphoneMotionManager *_motion;
    double _anchorYaw;
    BOOL _hasAnchor;
}

+ (instancetype)shared {
    static SGSpatialMotionTracker *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGSpatialMotionTracker new]; });
    return shared;
}

- (void)syncState {
    BOOL want = SGSpatialVoiceEnabled() && SGSingEnabled();
    if (!want) {
        if (_motion.isDeviceMotionActive) [_motion stopDeviceMotionUpdates];
        _hasAnchor = NO;
        storeFloat(&sg_relYawBits, 0.0f);
        return;
    }
    if (!_motion) {
        _motion = [CMHeadphoneMotionManager new];
        _motion.delegate = self;
    }
    if (_motion.isDeviceMotionAvailable && !_motion.isDeviceMotionActive) {
        __weak typeof(self) weakSelf = self;
        [_motion startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *motion, NSError *error) {
            if (!motion || error) return;
            [weakSelf handleMotion:motion];
        }];
    }
}

- (void)handleMotion:(CMDeviceMotion *)motion {
    double yaw = motion.attitude.yaw;
    if (!_hasAnchor) {
        _anchorYaw = yaw;
        _hasAnchor = YES;
    }
    double diff = yaw - _anchorYaw;
    while (diff > M_PI) diff -= 2.0 * M_PI;
    while (diff < -M_PI) diff += 2.0 * M_PI;

    int backMode = atomic_load_explicit(&sg_spatialBack, memory_order_relaxed);
    if (backMode > 0) {
        double recenterRate = (backMode == 1) ? 0.008 : ((backMode == 2) ? 0.022 : 0.055);
        _anchorYaw += diff * recenterRate;
    }
    float clamped = (float)fmax(-M_PI_2, fmin(M_PI_2, diff));
    storeFloat(&sg_relYawBits, clamped);
}

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    _hasAnchor = NO;
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    _hasAnchor = NO;
    storeFloat(&sg_relYawBits, 0.0f);
}

@end

void SGSingNotifySettingsChanged(void) {
    atomic_store_explicit(&sg_singFeatureOn, SGSingEnabled(), memory_order_relaxed);
    atomic_store_explicit(&sg_singLightMode, SGInt(SGKeySingLight, 0) == 1, memory_order_relaxed);
    storeFloat(&sg_singVocalLevelBits, SGSingVocalLevel());
    atomic_store_explicit(&sg_spatialOn, SGSpatialVoiceEnabled(), memory_order_relaxed);
    atomic_store_explicit(&sg_spatialDistance, (int)SGInt(SGKeySpatialVoiceDistance, 35), memory_order_relaxed);
    atomic_store_explicit(&sg_spatialRoom, (int)SGInt(SGKeySpatialVoiceRoom, 30), memory_order_relaxed);
    atomic_store_explicit(&sg_spatialBack, (int)SGInt(SGKeySpatialVoiceBack, 1), memory_order_relaxed);
    atomic_store_explicit(&sg_spatialWidth, (int)SGInt(SGKeySpatialVoiceWidth, 115), memory_order_relaxed);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SGSpatialMotionTracker shared] syncState];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"spotifyglass.singSpatialChanged" object:nil];
    });
}

#pragma mark - AudioUnit Real-Time Stem Separation & Spatial Voice Render

// Filter states for vocal core extraction (150 Hz .. 4400 Hz center vocal formant isolation)
static float sg_hpState1 = 0.0f, sg_hpState2 = 0.0f;
static float sg_lpState1 = 0.0f, sg_lpState2 = 0.0f;
static float sg_shadowL = 0.0f, sg_shadowR = 0.0f;
static float sg_itdLine[kSGSingMaxDelaySamples];
static uint32_t sg_itdWrite = 0;
static float sg_roomBufL[kSGSingRoomDelayL], sg_roomBufR[kSGSingRoomDelayR];
static uint32_t sg_roomIdxL = 0, sg_roomIdxR = 0;
static uint64_t sg_layoutPacked = 0;

static void processSingAndSpatial(float *left, float *right, UInt32 frames) {
    BOOL singActive = atomic_load_explicit(&sg_singFeatureOn, memory_order_relaxed) &&
                      atomic_load_explicit(&sg_singSessionActive, memory_order_relaxed);
    BOOL spatialOn = atomic_load_explicit(&sg_spatialOn, memory_order_relaxed) &&
                     atomic_load_explicit(&sg_singFeatureOn, memory_order_relaxed);
    if (!singActive && !spatialOn) return;

    float vocalSlider = singActive ? loadFloat(&sg_singVocalLevelBits) : 0.5f;
    float vocalGain = 1.0f;
    float instGain = 1.0f;
    if (singActive) {
        if (vocalSlider <= 0.5f) {
            // 0.0 -> 20% vocals (Karaoke), 0.5 -> 100% vocals (Original)
            vocalGain = 0.20f + (vocalSlider / 0.5f) * 0.80f;
            instGain = 1.0f;
        } else {
            // 0.5 -> 100% instruments, 1.0 -> 8% instruments (Vocals only)
            vocalGain = 1.0f;
            instGain = 1.0f - ((vocalSlider - 0.5f) / 0.5f) * 0.92f;
        }
    }

    float widthFactor = spatialOn ? (atomic_load_explicit(&sg_spatialWidth, memory_order_relaxed) / 100.0f) : 1.0f;
    float distFactor = spatialOn ? (atomic_load_explicit(&sg_spatialDistance, memory_order_relaxed) / 100.0f) : 0.0f;
    float roomFactor = spatialOn ? (atomic_load_explicit(&sg_spatialRoom, memory_order_relaxed) / 100.0f) : 0.0f;
    float relYaw = spatialOn ? loadFloat(&sg_relYawBits) : 0.0f;
    BOOL lightMode = atomic_load_explicit(&sg_singLightMode, memory_order_relaxed);

    // Panning & ITD parameters for 3D Spatial Voice
    float azimuth = -relYaw; // Voice stays in front when head turns
    float panAngle = (azimuth + (float)M_PI_2) * 0.5f; // 0..pi/2
    float gainL = cosf(panAngle), gainR = sinf(panAngle);
    float distAtten = 1.0f - 0.32f * distFactor;
    int itdSamples = (int)lrintf(sinf(azimuth) * 24.0f);
    int delayL = itdSamples > 0 ? itdSamples : 0;
    int delayR = itdSamples < 0 ? -itdSamples : 0;

    float vPeak = 0.0f, iPeak = 0.0f;

    for (UInt32 i = 0; i < frames; i++) {
        float L = left[i];
        float R = right[i];
        float mid = 0.5f * (L + R);
        float side = 0.5f * (L - R);

        // 2-stage vocal band isolation (~160 Hz - 4.4 kHz at 44.1/48 kHz)
        sg_hpState1 += 0.022f * (mid - sg_hpState1);
        float hp1 = mid - sg_hpState1;
        sg_lpState1 += 0.42f * (hp1 - sg_lpState1);
        float vocal = sg_lpState1;

        if (!lightMode) {
            // Second stage phase-coherent center reinforcement (reduces side bleed in center vocals)
            sg_hpState2 += 0.020f * (vocal - sg_hpState2);
            float hp2 = vocal - sg_hpState2;
            sg_lpState2 += 0.45f * (hp2 - sg_lpState2);
            float midE = fabsf(mid) + 1e-6f;
            float sideE = fabsf(side);
            float centerMask = fmaxf(0.0f, fminf(1.0f, 1.0f - 0.85f * (sideE / midE)));
            vocal = sg_lpState2 * (0.35f + 0.65f * centerMask);
        }

        // Instrument stem = original minus isolated vocal core, with stereo width adjustment
        float instMid = (mid - vocal) * instGain;
        float instSide = side * instGain * widthFactor;
        float instL = instMid + instSide;
        float instR = instMid - instSide;

        float vSample = vocal * vocalGain;
        float absV = fabsf(vSample);
        float absI = 0.5f * (fabsf(instL) + fabsf(instR));
        if (absV > vPeak) vPeak = absV;
        if (absI > iPeak) iPeak = absI;

        float vOutL = vSample;
        float vOutR = vSample;

        if (spatialOn) {
            sg_itdLine[sg_itdWrite] = vSample * distAtten;
            uint32_t readL = (sg_itdWrite + kSGSingMaxDelaySamples - (uint32_t)delayL) % kSGSingMaxDelaySamples;
            uint32_t readR = (sg_itdWrite + kSGSingMaxDelaySamples - (uint32_t)delayR) % kSGSingMaxDelaySamples;
            sg_itdWrite = (sg_itdWrite + 1) % kSGSingMaxDelaySamples;

            float dL = sg_itdLine[readL] * gainL * 1.414f;
            float dR = sg_itdLine[readR] * gainR * 1.414f;

            // Distance & head-shadow air absorption
            float alphaL = 0.85f - 0.35f * distFactor - (azimuth < 0 ? 0.25f * (-azimuth) : 0.0f);
            float alphaR = 0.85f - 0.35f * distFactor - (azimuth > 0 ? 0.25f * azimuth : 0.0f);
            sg_shadowL += fmaxf(0.15f, alphaL) * (dL - sg_shadowL);
            sg_shadowR += fmaxf(0.15f, alphaR) * (dR - sg_shadowR);

            // Early room reflections (Schroeder cross-coupled comb network)
            float revL = sg_roomBufL[sg_roomIdxL];
            float revR = sg_roomBufR[sg_roomIdxR];
            float fb = 0.28f * roomFactor;
            sg_roomBufL[sg_roomIdxL] = sg_shadowL + revR * fb;
            sg_roomBufR[sg_roomIdxR] = sg_shadowR + revL * fb;
            sg_roomIdxL = (sg_roomIdxL + 1) % kSGSingRoomDelayL;
            sg_roomIdxR = (sg_roomIdxR + 1) % kSGSingRoomDelayR;

            float wet = 0.38f * roomFactor;
            vOutL = sg_shadowL + revL * wet;
            vOutR = sg_shadowR + revR * wet;
        }

        left[i] = fmaxf(-1.0f, fminf(1.0f, instL + vOutL));
        right[i] = fmaxf(-1.0f, fminf(1.0f, instR + vOutR));
    }

    storeFloat(&sg_vocalPeakBits, fminf(1.0f, vPeak * 1.8f));
    storeFloat(&sg_instPeakBits, fminf(1.0f, iPeak * 1.8f));
}

static float sg_scratchL[4096], sg_scratchR[4096];

static OSStatus singRendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp,
                             UInt32 bus, UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    if (*flags & kAudioUnitRenderAction_OutputIsSilence) return noErr;
    BOOL singActive = atomic_load_explicit(&sg_singFeatureOn, memory_order_relaxed) &&
                      atomic_load_explicit(&sg_singSessionActive, memory_order_relaxed);
    BOOL spatialOn = atomic_load_explicit(&sg_spatialOn, memory_order_relaxed) &&
                     atomic_load_explicit(&sg_singFeatureOn, memory_order_relaxed);
    if (!singActive && !spatialOn) return noErr;

    if (data->mNumberBuffers >= 2 && data->mBuffers[0].mData && data->mBuffers[1].mData &&
        data->mBuffers[0].mDataByteSize == frames * sizeof(float)) {
        processSingAndSpatial((float *)data->mBuffers[0].mData, (float *)data->mBuffers[1].mData, frames);
    } else if (data->mNumberBuffers == 1 && data->mBuffers[0].mNumberChannels == 2 && data->mBuffers[0].mData) {
        UInt32 total = MIN(frames, 4096u);
        if (data->mBuffers[0].mDataByteSize == frames * 2 * sizeof(float)) {
            float *interleaved = (float *)data->mBuffers[0].mData;
            for (UInt32 i = 0; i < total; i++) {
                sg_scratchL[i] = interleaved[i * 2];
                sg_scratchR[i] = interleaved[i * 2 + 1];
            }
            processSingAndSpatial(sg_scratchL, sg_scratchR, total);
            for (UInt32 i = 0; i < total; i++) {
                interleaved[i * 2] = sg_scratchL[i];
                interleaved[i * 2 + 1] = sg_scratchR[i];
            }
        } else if (data->mBuffers[0].mDataByteSize == frames * 2 * sizeof(int16_t)) {
            int16_t *interleaved = (int16_t *)data->mBuffers[0].mData;
            for (UInt32 i = 0; i < total; i++) {
                sg_scratchL[i] = interleaved[i * 2] / 32768.0f;
                sg_scratchR[i] = interleaved[i * 2 + 1] / 32768.0f;
            }
            processSingAndSpatial(sg_scratchL, sg_scratchR, total);
            for (UInt32 i = 0; i < total; i++) {
                interleaved[i * 2] = (int16_t)lrintf(fmaxf(-32768.0f, fminf(32767.0f, sg_scratchL[i] * 32768.0f)));
                interleaved[i * 2 + 1] = (int16_t)lrintf(fmaxf(-32768.0f, fminf(32767.0f, sg_scratchR[i] * 32768.0f)));
            }
        }
    }
    return noErr;
}

static OSStatus (*sg_origStartOutput)(AudioUnit unit);

static OSStatus singStartOutput(AudioUnit unit) {
    AudioComponentDescription desc = {0};
    if (unit && AudioComponentGetDescription(AudioComponentInstanceGetComponent(unit), &desc) == noErr) {
        if (desc.componentType == kAudioUnitType_Output && desc.componentSubType == kAudioUnitSubType_RemoteIO) {
            AudioUnitRemoveRenderNotify(unit, singRendered, NULL);
            AudioUnitAddRenderNotify(unit, singRendered, NULL);
        }
    }
    return sg_origStartOutput(unit);
}

%ctor {
    SGSingNotifySettingsChanged();
    SGRebindImport("AudioOutputUnitStart", singStartOutput, (void **)&sg_origStartOutput);
}
