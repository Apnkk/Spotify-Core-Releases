// The Vibrations page & sections, with the 1:1 Chroma 0.51.0 3D Metal particle wave stage,
// Controls strength, Music Haptics strength, Follows mode, and In the Background support.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Haptics.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

static NSString *const kMusicHapticsInfo = @"The iPhone taps along with the drums and rumbles under the bass of whatever Spotify is playing, worked out from the sound as it plays, much like Music Haptics in Apple Music.";

static NSArray<NSString *> *followsNames(void) {
    return @[@"Everything", @"Beat", @"Bass"];
}

static NSArray<NSString *> *followsNotes(void) {
    return @[@"A tap on each kick and snare, and a rumble under the bass",
             @"A tap on each kick and snare, no rumble",
             @"A tap on each kick, and a rumble under the bass"];
}

static void strengthRange(NSString *key, NSInteger *minimum, NSInteger *maximum) {
    BOOL music = [key isEqualToString:SGKeyMusicStrength];
    *minimum = music ? SGMusicStrengthMin : SGControlStrengthMin;
    *maximum = music ? SGMusicStrengthMax : SGControlStrengthMax;
}

double SGHapticsStrength(NSString *key) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return MAX(minimum, MIN(maximum, SGInt(key, 100))) / 100.0;
}

SGMusicFollows SGMusicHapticsFollows(void) {
    NSInteger follows = SGInt(SGKeyMusicFollows, SGMusicFollowsEverything);
    return follows >= SGMusicFollowsEverything && follows <= SGMusicFollowsBass ? (SGMusicFollows)follows : SGMusicFollowsEverything;
}

static SGModRow *strengthRow(NSString *key, void (^changed)(void)) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return SGSliderRow(@"Strength", nil, minimum, maximum, SGStrengthStep,
        ^double { return SGHapticsStrength(key) * 100; },
        ^(double value) {
            SGSetInt(key, lround(value));
            if (changed) changed();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });
}

#pragma mark - SGVibrationsScene (1:1 Chroma 0.51.0 Metal 3D Particle Wave & Spring Orb Stage)

typedef struct {
    simd_float2 center;
    float radius;
    float kind;
    simd_float4 color;
} SGVibSprite;

typedef struct {
    simd_float2 size;
    float pixel;
    float pad;
} SGVibFrame;

typedef struct {
    float x, z, r;
} SGVibDot;

typedef struct {
    float age;
    float strength;
    BOOL active;
} SGVibHit;

static NSString *const kSGVibrationsMetalShader =
@"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct Sprite { float2 center; float radius; float kind; float4 color; };\n"
"struct Frame { float2 size; float pixel; float pad; };\n"
"struct Fragment {\n"
"    float4 position [[position]];\n"
"    float2 local;\n"
"    float radius [[flat]];\n"
"    float kind [[flat]];\n"
"    float4 color [[flat]];\n"
"};\n"
"vertex Fragment spriteVertex(uint v [[vertex_id]], uint i [[instance_id]], const device Sprite *sprites [[buffer(0)]],\n"
"                             constant Frame &frame [[buffer(1)]]) {\n"
"    Sprite s = sprites[i];\n"
"    float2 corner = float2((v & 1) ? 1.0f : -1.0f, (v & 2) ? 1.0f : -1.0f) * (s.radius + frame.pixel);\n"
"    float2 p = s.center + corner;\n"
"    Fragment out;\n"
"    out.position = float4(p.x / frame.size.x * 2.0f - 1.0f, 1.0f - p.y / frame.size.y * 2.0f, 0.0f, 1.0f);\n"
"    out.local = corner;\n"
"    out.radius = s.radius;\n"
"    out.kind = s.kind;\n"
"    out.color = s.color;\n"
"    return out;\n"
"}\n"
"fragment half4 spriteFragment(Fragment in [[stage_in]], constant Frame &frame [[buffer(0)]]) {\n"
"    float d = length(in.local);\n"
"    if (in.kind < 0.5f) return half4(in.color * saturate((in.radius - d) / frame.pixel + 0.5f));\n"
"    float t = d / in.radius, a = in.color.a, loud = in.kind - 1.0f;\n"
"    float3 accent = in.color.rgb, light = mix(accent, float3(1.0f), 0.5f);\n"
"    float4 core = float4(a), inner = float4(light, 1.0f) * 0.95f * a, outer = float4(accent, 1.0f) * 0.32f * a * (0.6f + 0.4f * loud);\n"
"    float4 c = t < 0.16f ? mix(core, inner, t / 0.16f) : t < 0.34f ? mix(inner, outer, (t - 0.16f) / 0.18f) : mix(outer, float4(0.0f), saturate((t - 0.34f) / 0.66f));\n"
"    return half4(c);\n"
"}\n";

@interface SGVibrationsScene : UIView
@end

@implementation SGVibrationsScene {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    UILabel *_caption;
    CADisplayLink *_link;
    CFTimeInterval _lastTime;

    SGVibDot *_dots;
    int _dotCount;
    SGVibSprite *_sprites;
    float *_depths;
    int *_order;
    int _maxSprites;

    SGVibHit _hits[12];
    double _clock;
    int _lastBeatStep;
    float _bounceY;
    float _bounceVel;
    float _flash;
    float _bassRumble;
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    _lastBeatStep = -1;

    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    _device = MTLCreateSystemDefaultDevice();
    if (_device) {
        metalLayer.device = _device;
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.framebufferOnly = YES;
        metalLayer.opaque = NO;
        metalLayer.contentsScale = UIScreen.mainScreen.scale;
        _queue = [_device newCommandQueue];

        NSError *err = nil;
        id<MTLLibrary> lib = [_device newLibraryWithSource:kSGVibrationsMetalShader options:nil error:&err];
        if (lib) {
            MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
            desc.vertexFunction = [lib newFunctionWithName:@"spriteVertex"];
            desc.fragmentFunction = [lib newFunctionWithName:@"spriteFragment"];
            MTLRenderPipelineColorAttachmentDescriptor *att = desc.colorAttachments[0];
            att.pixelFormat = MTLPixelFormatBGRA8Unorm;
            att.blendingEnabled = YES;
            att.sourceRGBBlendFactor = MTLBlendFactorOne;
            att.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            att.sourceAlphaBlendFactor = MTLBlendFactorOne;
            att.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            _pipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&err];
        }
    }

    // Build 25 concentric floor rings (exact Chroma 0.51.0 geometry: r = 0.20 + i * 0.095, spacing = 0.068)
    int total = 0;
    for (int ring = 0; ring < 25; ring++) {
        float r = 0.20f + (float)ring * 0.095f;
        int cnt = (int)lrintf((r * 2.0f * (float)M_PI) / 0.068f);
        total += cnt;
    }
    _dotCount = total;
    _dots = (SGVibDot *)calloc((size_t)total, sizeof(SGVibDot));
    int idx = 0;
    for (int ring = 0; ring < 25; ring++) {
        float r = 0.20f + (float)ring * 0.095f;
        int cnt = (int)lrintf((r * 2.0f * (float)M_PI) / 0.068f);
        for (int j = 0; j < cnt; j++) {
            float a = ((float)j / (float)cnt) * 2.0f * (float)M_PI;
            _dots[idx++] = (SGVibDot){ sinf(a) * r, -cosf(a) * r, r };
        }
    }

    _maxSprites = _dotCount + 2;
    _sprites = (SGVibSprite *)calloc((size_t)_maxSprites, sizeof(SGVibSprite));
    _depths = (float *)calloc((size_t)_maxSprites, sizeof(float));
    _order = (int *)calloc((size_t)_maxSprites, sizeof(int));

    _caption = [UILabel new];
    _caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _caption.textColor = [UIColor colorWithWhite:1.0 alpha:0.48];
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.numberOfLines = 2;
    [self addSubview:_caption];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    [self addGestureRecognizer:tap];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultsChanged) name:NSUserDefaultsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    free(_dots);
    free(_sprites);
    free(_depths);
    free(_order);
}

- (void)defaultsChanged {
    // Immediate visual sync when user toggles switches or sliders
}

- (void)spawnHitWithStrength:(float)strength {
    int slot = 0;
    float oldest = -1.0f;
    for (int i = 0; i < 12; i++) {
        if (!_hits[i].active) {
            slot = i;
            break;
        }
        if (_hits[i].age > oldest) {
            oldest = _hits[i].age;
            slot = i;
        }
    }
    _hits[slot] = (SGVibHit){ .age = 0.0f, .strength = strength, .active = YES };
    _bounceVel += 2.65f * strength;
    _flash = fminf(1.0f, _flash + 0.78f * strength);
}

- (void)tapped {
    float ctrlStr = (float)SGHapticsStrength(SGKeyControlStrength);
    [self spawnHitWithStrength:fmaxf(0.55f, ctrlStr)];
    SGPlayFeedback(SGFeedbackPlay);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    if (self.window) {
        _lastTime = CACurrentMediaTime();
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    _caption.frame = CGRectMake(20.0, h - 32.0, w - 40.0, 24.0);
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    CGFloat scale = UIScreen.mainScreen.scale;
    metalLayer.contentsScale = scale;
    metalLayer.drawableSize = CGSizeMake(w * scale, h * scale);
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    float dt = (float)(now - _lastTime);
    _lastTime = now;
    if (dt <= 0.0f || dt > 0.1f) dt = 1.0f / 60.0f;
    _clock += dt;

    BOOL controlsOn = SGEnabled(SGKeyControlHaptics);
    BOOL musicOn = SGFlag(SGKeyMusicHaptics, NO);
    float musicStrength = (float)SGHapticsStrength(SGKeyMusicStrength);
    SGMusicFollows follows = SGMusicHapticsFollows();

    // Update caption (exact Chroma 0.51.0 strings)
    if (musicOn) {
        if (follows == SGMusicFollowsBeat) {
            _caption.text = @"Preview · Taps on each kick and snare";
        } else if (follows == SGMusicFollowsBass) {
            _caption.text = @"Preview · Taps on the kick, rumbles under the bass";
        } else {
            _caption.text = @"Preview · Taps on the drums, rumbles under the bass";
        }
    } else if (controlsOn) {
        _caption.text = @"Tap to feel a control vibration";
    } else {
        _caption.text = @"Off — tap to preview";
    }

    // 116 BPM demo beat pattern when Music Haptics is enabled
    if (musicOn) {
        double subStepDur = 0.2586; // eighth-note at 116 BPM
        int step = (int)floor(_clock / subStepDur);
        if (step != _lastBeatStep) {
            _lastBeatStep = step;
            int barStep = step & 7;
            // Kick on 0, 3, 4; Snare on 2, 6
            if (barStep == 0 || barStep == 3 || barStep == 4) {
                float str = (barStep == 0 ? 0.95f : 0.72f) * (0.45f + 0.55f * musicStrength);
                [self spawnHitWithStrength:str];
            } else if ((barStep == 2 || barStep == 6) && follows != SGMusicFollowsBass) {
                float str = 0.78f * (0.45f + 0.55f * musicStrength);
                [self spawnHitWithStrength:str];
            }
        }
        if (follows != SGMusicFollowsBeat) {
            float targetRumble = (0.38f + 0.34f * sinf((float)_clock * 4.8f) + 0.20f * sinf((float)_clock * 11.2f)) * (0.5f + 0.5f * musicStrength);
            _bassRumble += (targetRumble - _bassRumble) * fminf(1.0f, dt * 8.0f);
        } else {
            _bassRumble *= expf(-dt * 6.0f);
        }
    } else {
        _bassRumble *= expf(-dt * 6.0f);
    }

    // Advance shockwaves
    for (int i = 0; i < 12; i++) {
        if (!_hits[i].active) continue;
        _hits[i].age += dt;
        if (_hits[i].age > 1.85f) _hits[i].active = NO;
    }

    // 4-substep spring physics on central orb (exact Chroma 0.51.0 constants: k = -696.4, c = -20.05)
    float subDt = dt * 0.25f;
    for (int s = 0; s < 4; s++) {
        float acc = -696.4f * _bounceY - 20.05f * _bounceVel;
        _bounceVel += acc * subDt;
        _bounceY += _bounceVel * subDt;
    }
    _flash *= expf(-dt * 5.2f);

    [self renderStageWithActive:(controlsOn || musicOn)];
}

- (void)renderStageWithActive:(BOOL)active {
    if (!_pipeline || !_queue) return;
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
    if (!drawable) return;

    CGFloat scale = metalLayer.contentsScale;
    float W = (float)metalLayer.drawableSize.width;
    float H = (float)metalLayer.drawableSize.height;
    if (W <= 10.0f || H <= 10.0f) return;

    float cx = W * 0.5f;
    float cy = H * 0.49f;
    float fov = fminf(W, H) * 0.88f;
    float pitch = 0.52f;
    float cp = cosf(pitch), sp = sinf(pitch);
    float floorY = -0.34f;

    int count = 0;

    // 1. 25 concentric floor rings with shockwave propagation and bass rumble
    for (int i = 0; i < _dotCount; i++) {
        SGVibDot d = _dots[i];
        float waveY = 0.0f;
        float waveGlow = 0.0f;

        for (int h = 0; h < 12; h++) {
            if (!_hits[h].active) continue;
            float waveRadius = 0.16f + _hits[h].age * 1.45f;
            float dist = d.r - waveRadius;
            float env = expf(-(dist * dist) / 0.022f) * expf(-_hits[h].age * 1.55f) * _hits[h].strength;
            waveY += env * 0.095f * cosf(dist * 14.0f);
            waveGlow += env;
        }

        if (_bassRumble > 0.01f) {
            float rumbleEnv = expf(-d.r * 0.85f) * _bassRumble;
            waveY += sinf(d.r * 10.0f - (float)_clock * 9.5f) * 0.028f * rumbleEnv;
            waveGlow += rumbleEnv * 0.45f;
        }

        float y = floorY + waveY;
        float ry = y * cp - d.z * sp;
        float rz = y * sp + d.z * cp;
        float camZ = fmaxf(0.2f, 2.55f + rz);
        float persp = fov / camZ;
        float sx = cx + d.x * persp;
        float sy = cy - ry * persp;

        float ringFade = fmaxf(0.0f, 1.0f - (d.r - 0.20f) / 2.35f);
        float glow = fminf(1.0f, waveGlow);
        float alpha = (0.12f + 0.24f * ringFade + 0.58f * glow) * (0.50f + 0.50f * ringFade);
        alpha = fminf(0.95f, fmaxf(0.04f, alpha));

        float greenMix = active ? fminf(1.0f, glow * 1.15f + _bassRumble * 0.35f) : 0.0f;
        float rCol = (1.0f - greenMix) * 1.0f + greenMix * 0.118f;
        float gCol = (1.0f - greenMix) * 1.0f + greenMix * 0.843f;
        float bCol = (1.0f - greenMix) * 1.0f + greenMix * 0.376f;

        float radPx = fmaxf(1.1f * (float)scale, (1.55f + 1.35f * glow) * (persp / fov) * (float)scale);
        _sprites[count] = (SGVibSprite){
            .center = { sx, sy },
            .radius = radPx,
            .kind = 0.0f,
            .color = { rCol * alpha, gCol * alpha, bCol * alpha, alpha }
        };
        _depths[count] = camZ;
        _order[count] = count;
        count++;
    }

    // 2. Central spring-bouncing glowing orb at (0, floorY + 0.12 + _bounceY, 0)
    {
        float y = floorY + 0.12f + _bounceY;
        float ry = y * cp;
        float rz = y * sp;
        float camZ = fmaxf(0.2f, 2.55f + rz);
        float persp = fov / camZ;
        float sx = cx;
        float sy = cy - ry * persp;

        float loud = fminf(1.0f, _flash + _bassRumble * 0.55f);
        float radPx = (30.0f + 16.0f * loud) * (persp / fov) * (float)scale;
        float a = active ? 0.96f : 0.58f;
        float rCol = active ? 0.118f : 0.75f;
        float gCol = active ? 0.843f : 0.78f;
        float bCol = active ? 0.376f : 0.82f;

        _sprites[count] = (SGVibSprite){
            .center = { sx, sy },
            .radius = radPx,
            .kind = 1.0f + loud,
            .color = { rCol, gCol, bCol, a }
        };
        _depths[count] = camZ - 0.08f;
        _order[count] = count;
        count++;
    }

    // Back-to-front depth sort
    for (int i = 1; i < count; i++) {
        int keyIdx = _order[i];
        float keyDepth = _depths[keyIdx];
        int j = i - 1;
        while (j >= 0 && _depths[_order[j]] < keyDepth) {
            _order[j + 1] = _order[j];
            j--;
        }
        _order[j + 1] = keyIdx;
    }

    id<MTLBuffer> spriteBuf = [_device newBufferWithLength:(NSUInteger)count * sizeof(SGVibSprite)
                                                   options:MTLResourceStorageModeShared];
    SGVibSprite *dst = (SGVibSprite *)spriteBuf.contents;
    for (int i = 0; i < count; i++) {
        dst[i] = _sprites[_order[i]];
    }

    SGVibFrame frameUni = { .size = { W, H }, .pixel = (float)scale, .pad = 0.0f };

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);

    id<MTLCommandBuffer> cmd = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:_pipeline];
    [enc setVertexBuffer:spriteBuf offset:0 atIndex:0];
    [enc setVertexBytes:&frameUni length:sizeof(frameUni) atIndex:1];
    [enc setFragmentBytes:&frameUni length:sizeof(frameUni) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:(NSUInteger)count];
    [enc endEncoding];
    [cmd presentDrawable:drawable];
    [cmd commit];
}

@end

NSArray<SGModSection *> *SGVibrationsSections(void) {
    SGModRow *controls = SGSwitchRow(@"Controls", @"Tactile feedback on play, skip, scrub and buttons", SGKeyControlHaptics);
    SGModRow *controlStrength = strengthRow(SGKeyControlStrength, ^{
        SGPlayFeedback(SGFeedbackAdd);
    });
    controlStrength.visible = ^BOOL { return SGEnabled(SGKeyControlHaptics); };

    SGModRow *music = SGOptionRow(@"Music Haptics", @"Taps on the drums and rumbles under the bass", SGKeyMusicHaptics);
    music.info = kMusicHapticsInfo;
    music.changed = ^(BOOL on) { SGSetMusicHapticsEnabled(on); };
    BOOL (^musicOn)(void) = ^BOOL { return SGFlag(SGKeyMusicHaptics, NO); };
    SGModRow *musicStrength = strengthRow(SGKeyMusicStrength, ^{ SGMusicHapticsSettingsChanged(); });
    musicStrength.visible = musicOn;
    SGModRow *follows = SGChoiceRow(@"Follows", nil, SGKeyMusicFollows, followsNames(), SGMusicFollowsEverything);
    follows.choiceNotes = followsNotes();
    follows.chosen = ^(NSInteger index) { SGMusicHapticsSettingsChanged(); };
    follows.visible = musicOn;
    SGModRow *bgRow = SGOptionRow(@"In the Background", @"Keep Music Haptics active while the screen is locked or another app is open", SGKeyMusicHapticsBackground);
    bgRow.changed = ^(BOOL on) { SGMusicHapticsSettingsChanged(); };
    bgRow.visible = musicOn;

    return @[
        SGSection(@"Vibrations", @[SGWithSymbol(controls, @"hand.tap"), controlStrength]),
        SGSection(nil, @[SGWithSymbol(music, @"waveform"), musicStrength, follows, bgRow]),
    ];
}

NSString *SGVibrationsSummary(void) {
    BOOL c = SGEnabled(SGKeyControlHaptics);
    BOOL m = SGFlag(SGKeyMusicHaptics, NO);
    if (c && m) return @"Controls & Music";
    if (m) return @"Music";
    if (c) return @"Controls";
    return @"Off";
}

UIViewController *SGVibrationsSettingsPage(void) {
    SGVibrationsScene *scene = [[SGVibrationsScene alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[SGCustomViewRow(scene, 300.0)])];
    [sections addObjectsFromArray:SGVibrationsSections()];
    return [[SGModPage alloc] initWithTitle:@"Vibrations" intro:nil sections:sections footer:nil];
}
