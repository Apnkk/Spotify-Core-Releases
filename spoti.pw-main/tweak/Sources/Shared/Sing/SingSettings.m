#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Sing.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

#pragma mark - SGRSingDemoCapsule (1:1 Chroma 0.51.0 Interactive Mic Pill)

@interface SGRSingDemoCapsule : UIView
@property (nonatomic, copy) void (^changed)(float level, BOOL open);
@property (nonatomic, readonly) float level;
@property (nonatomic, readonly) BOOL open;
@end

@implementation SGRSingDemoCapsule {
    UIVisualEffectView *_bg;
    UIView *_tint;
    UIView *_fill;
    UIView *_tick;
    UIImageView *_icon;
    CAShapeLayer *_border;
    UIImpactFeedbackGenerator *_haptic;
    float _panStart;
    BOOL _snapped;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _level = 0.10f;
    _open = YES;
    _snapped = NO;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    _bg = [[UIVisualEffectView alloc] initWithEffect:blur];
    _bg.layer.cornerRadius = 17.0;
    _bg.layer.cornerCurve = kCACornerCurveContinuous;
    _bg.clipsToBounds = YES;
    [self addSubview:_bg];

    _tint = [UIView new];
    _tint.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [_bg.contentView addSubview:_tint];

    _fill = [UIView new];
    _fill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    [_bg.contentView addSubview:_fill];

    _tick = [UIView new];
    _tick.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    [_bg.contentView addSubview:_tick];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightSemibold];
    _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"mic.fill" withConfiguration:cfg]];
    _icon.tintColor = UIColor.whiteColor;
    _icon.contentMode = UIViewContentModeCenter;
    [_bg.contentView addSubview:_icon];

    _border = [CAShapeLayer layer];
    _border.fillColor = UIColor.clearColor.CGColor;
    _border.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    _border.lineWidth = 0.5;
    [self.layer addSublayer:_border];

    _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [self addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat pillW = 34.0;
    CGFloat pillH = _open ? h : 34.0;
    CGRect pillRect = CGRectMake((w - pillW) * 0.5, h - pillH, pillW, pillH);

    _bg.frame = pillRect;
    _tint.frame = _bg.contentView.bounds;

    CGFloat fillH = _open ? (pillH * (CGFloat)_level) : 0.0;
    _fill.frame = CGRectMake(0, pillH - fillH, pillW, fillH);
    _fill.alpha = _open ? 1.0 : 0.0;

    _tick.frame = CGRectMake(8.0, pillH * 0.5 - 0.5, pillW - 16.0, 1.0);
    _tick.alpha = _open ? 1.0 : 0.0;

    _icon.frame = CGRectMake(0, pillH - 34.0, pillW, 34.0);
    _border.path = [UIBezierPath bezierPathWithRoundedRect:pillRect cornerRadius:17.0].CGPath;
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    CGPoint pt = [tap locationInView:_bg];
    [_haptic impactOccurred];
    if (_open && pt.y < _bg.bounds.size.height - 34.0) {
        CGFloat usable = MAX(1.0, _bg.bounds.size.height - 34.0);
        float raw = (float)(1.0 - fmin(1.0, fmax(0.0, pt.y / usable)));
        if (fabsf(raw - 0.5f) < 0.05f) raw = 0.5f;
        _level = raw;
        [self setNeedsLayout];
        [UIView animateWithDuration:0.18 animations:^{ [self layoutIfNeeded]; }];
        if (self.changed) self.changed(_level, _open);
        return;
    }
    _open = !_open;
    [self setNeedsLayout];
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self layoutIfNeeded];
    } completion:nil];
    if (self.changed) self.changed(_level, _open);
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    if (!_open) {
        if (pan.state == UIGestureRecognizerStateBegan) {
            _open = YES;
            [_haptic impactOccurred];
            [self setNeedsLayout];
            [UIView animateWithDuration:0.25 animations:^{ [self layoutIfNeeded]; }];
        } else {
            return;
        }
    }
    if (pan.state == UIGestureRecognizerStateBegan) {
        _panStart = _level;
        _snapped = (fabsf(_level - 0.5f) < 0.04f);
        [_haptic prepare];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint tr = [pan translationInView:self];
        CGFloat range = MAX(60.0, self.bounds.size.height - 44.0);
        float raw = fminf(1.0f, fmaxf(0.0f, _panStart - (float)(tr.y / range)));
        if (fabsf(raw - 0.5f) < 0.04f) {
            raw = 0.5f;
            if (!_snapped) {
                _snapped = YES;
                [_haptic impactOccurred];
            }
        } else {
            _snapped = NO;
        }
        _level = raw;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        if (self.changed) self.changed(_level, _open);
    }
}

@end

#pragma mark - SGRSingDemo (1:1 Chroma 0.51.0 Interactive Waveform Demo Card)

@interface SGRSingDemo : UIView
@end

@implementation SGRSingDemo {
    UIView *_card;
    UIView *_waveBox;
    CAShapeLayer *_echo;
    CAShapeLayer *_instruments;
    CAShapeLayer *_voice;
    UILabel *_title;
    UILabel *_value;
    UIView *_voiceTag;
    UIView *_musicTag;
    UILabel *_hint;
    SGRSingDemoCapsule *_capsule;
    CADisplayLink *_link;
    double _phase;
}

static UIView *makeLegendTag(NSString *text, UIColor *dotColor) {
    UIView *box = [UIView new];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 3, 6, 6)];
    dot.backgroundColor = dotColor;
    dot.layer.cornerRadius = 3.0;
    [box addSubview:dot];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 48, 12)];
    lbl.text = text;
    lbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    lbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    [box addSubview:lbl];
    return box;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;

    _card = [UIView new];
    _card.backgroundColor = SGCardSurfaceColor();
    _card.layer.cornerRadius = 16.0;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.borderWidth = 1.0;
    _card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
    _card.clipsToBounds = YES;
    [self addSubview:_card];

    _waveBox = [UIView new];
    [_card addSubview:_waveBox];

    _echo = [CAShapeLayer layer];
    _echo.fillColor = UIColor.clearColor.CGColor;
    _echo.strokeColor = SGGreen().CGColor;
    _echo.lineWidth = 5.0;
    _echo.lineCap = kCALineCapRound;
    [_waveBox.layer addSublayer:_echo];

    _instruments = [CAShapeLayer layer];
    _instruments.fillColor = UIColor.clearColor.CGColor;
    _instruments.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
    _instruments.lineWidth = 2.0;
    _instruments.lineCap = kCALineCapRound;
    [_waveBox.layer addSublayer:_instruments];

    _voice = [CAShapeLayer layer];
    _voice.fillColor = UIColor.clearColor.CGColor;
    _voice.strokeColor = SGGreen().CGColor;
    _voice.lineWidth = 2.5;
    _voice.lineCap = kCALineCapRound;
    [_waveBox.layer addSublayer:_voice];

    _title = [UILabel new];
    _title.text = @"Sing";
    _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    [_card addSubview:_title];

    _value = [UILabel new];
    _value.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    _value.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    [_card addSubview:_value];

    _voiceTag = makeLegendTag(@"VOICE", SGGreen());
    _musicTag = makeLegendTag(@"MUSIC", [UIColor colorWithWhite:1.0 alpha:0.55]);
    [_card addSubview:_voiceTag];
    [_card addSubview:_musicTag];

    _capsule = [[SGRSingDemoCapsule alloc] initWithFrame:CGRectZero];
    __weak typeof(self) weakSelf = self;
    _capsule.changed = ^(float level, BOOL open) {
        SGSetSingVocalLevel(level);
        SGSetSingActive(open);
        SGSingNotifySettingsChanged();
        [weakSelf updateReadout];
    };
    [_card addSubview:_capsule];

    _hint = [UILabel new];
    _hint.text = @"20% vocals at the bottom · Original in the middle · Vocals only at the top";
    _hint.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 2;
    [self addSubview:_hint];

    [self updateReadout];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    if (self.window) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)updateReadout {
    if (!_capsule.open) {
        _value.text = @"Off — original mix";
        _hint.text = @"Tap the mic, then drag up or down";
        return;
    }
    _hint.text = @"20% vocals at the bottom · Original in the middle · Vocals only at the top";
    float l = _capsule.level;
    if (fabsf(l - 0.5f) < 0.04f) {
        _value.text = @"Original";
    } else if (l > 0.94f) {
        _value.text = @"Vocals only";
    } else if (l < 0.5f) {
        int pct = (int)lrintf(20.0f + (l / 0.5f) * 80.0f);
        _value.text = [NSString stringWithFormat:@"%d%% vocals", pct];
    } else {
        int pct = (int)lrintf(100.0f - ((l - 0.5f) / 0.5f) * 100.0f);
        _value.text = [NSString stringWithFormat:@"Vocals · %d%% music", pct];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _card.frame = CGRectMake(20.0, 4.0, w - 40.0, 148.0);
    CGFloat cw = _card.bounds.size.width;
    _title.frame = CGRectMake(16.0, 14.0, 60.0, 18.0);
    _value.frame = CGRectMake(68.0, 15.0, cw - 130.0, 16.0);
    _waveBox.frame = CGRectMake(16.0, 38.0, cw - 74.0, 78.0);
    _voiceTag.frame = CGRectMake(16.0, 122.0, 56.0, 14.0);
    _musicTag.frame = CGRectMake(78.0, 122.0, 56.0, 14.0);
    _capsule.frame = CGRectMake(cw - 48.0, 12.0, 36.0, 124.0);
    _hint.frame = CGRectMake(20.0, 158.0, w - 40.0, 32.0);
}

- (void)tick:(CADisplayLink *)link {
    _phase += link.duration * 2.8;
    CGFloat w = _waveBox.bounds.size.width;
    CGFloat h = _waveBox.bounds.size.height;
    if (w <= 10.0 || h <= 10.0) return;

    float lvl = _capsule.open ? _capsule.level : 0.5f;
    float vScale = (lvl <= 0.5f) ? (0.20f + (lvl / 0.5f) * 0.80f) : 1.0f;
    float iScale = (lvl <= 0.5f) ? 1.0f : fmaxf(0.06f, 1.0f - ((lvl - 0.5f) / 0.5f) * 0.94f);

    UIBezierPath *vPath = [UIBezierPath bezierPath];
    UIBezierPath *iPath = [UIBezierPath bezierPath];
    CGFloat midY = h * 0.5;
    int steps = 72;

    for (int i = 0; i <= steps; i++) {
        double t = (double)i / (double)steps;
        CGFloat x = (CGFloat)t * w;
        double env = sin(t * M_PI);
        double p = t * 10.0 - _phase;

        double iWave = 0.55 * sin(p) + 0.30 * sin(p * 2.3 + 1.1) + 0.15 * sin(p * 4.1 - 0.7);
        double vWave = 0.60 * sin(p * 1.4 + 0.4) + 0.25 * sin(p * 3.1 - 1.2) + 0.15 * sin(p * 5.3 + 2.0);

        CGFloat iy = midY + (CGFloat)(iWave * env * (h * 0.36) * iScale);
        CGFloat vy = midY + (CGFloat)(vWave * env * (h * 0.40) * vScale);

        if (i == 0) {
            [iPath moveToPoint:CGPointMake(x, iy)];
            [vPath moveToPoint:CGPointMake(x, vy)];
        } else {
            [iPath addLineToPoint:CGPointMake(x, iy)];
            [vPath addLineToPoint:CGPointMake(x, vy)];
        }
    }

    _instruments.path = iPath.CGPath;
    _instruments.opacity = 0.25f + 0.55f * iScale;
    _voice.path = vPath.CGPath;
    _voice.opacity = 0.30f + 0.70f * vScale;
    _echo.path = vPath.CGPath;
    _echo.opacity = 0.22f * vScale;
}

@end

#pragma mark - SGRSpatialVoiceScene (1:1 Chroma 0.51.0 Metal 3D Particle Stage)

typedef struct {
    simd_float2 center;
    float radius;
    float kind;
    simd_float4 color;
} SGMetalSprite;

typedef struct {
    simd_float2 size;
    float pixel;
    float pad;
} SGMetalFrame;

typedef struct {
    float x, z, r, angle;
} SGFloorDot;

typedef struct {
    float x, y, z;
    int isEar;
} SGHeadDot;

static NSString *const kSGSpriteMetalShader =
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

@interface SGRSpatialVoiceScene : UIView
@end

@implementation SGRSpatialVoiceScene {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    UILabel *_caption;
    CADisplayLink *_link;
    CFTimeInterval _lastTime;

    SGFloorDot *_floorDots;
    int _floorCount;
    SGHeadDot _headDots[262];
    int _headCount;
    SGMetalSprite *_sprites;
    float *_depths;
    int *_order;
    int _maxSprites;

    double _clock;
    double _nextDemoSwitch;
    int _demoIndex;
    float _headYaw;
    float _headVel;
    float _headTarget;
    float _voiceYaw;
    float _voiceLevel;
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;

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
        id<MTLLibrary> lib = [_device newLibraryWithSource:kSGSpriteMetalShader options:nil error:&err];
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

    // Build 20 concentric floor rings (exact Chroma 0.51.0 geometry: r = 0.32 + i * 0.11, spacing = 0.07)
    int totalFloor = 0;
    for (int ring = 0; ring < 20; ring++) {
        float r = 0.32f + (float)ring * 0.11f;
        int cnt = (int)lrintf((r * 2.0f * (float)M_PI) / 0.07f);
        totalFloor += cnt;
    }
    _floorCount = totalFloor;
    _floorDots = (SGFloorDot *)calloc((size_t)totalFloor, sizeof(SGFloorDot));
    int idx = 0;
    for (int ring = 0; ring < 20; ring++) {
        float r = 0.32f + (float)ring * 0.11f;
        int cnt = (int)lrintf((r * 2.0f * (float)M_PI) / 0.07f);
        for (int j = 0; j < cnt; j++) {
            float a = ((float)j / (float)cnt) * 2.0f * (float)M_PI;
            _floorDots[idx++] = (SGFloorDot){ sinf(a) * r, -cosf(a) * r, r, a };
        }
    }

    // Build 260-dot 3D Fibonacci sphere head + 2 ear markers (exact Chroma 0.51.0 geometry: radius = 0.19)
    float golden = (float)M_PI * (3.0f - sqrtf(5.0f));
    for (int i = 0; i < 260; i++) {
        float y = 1.0f - ((float)i / 259.0f) * 2.0f;
        float rad = sqrtf(fmaxf(0.0f, 1.0f - y * y));
        float theta = golden * (float)i;
        _headDots[i] = (SGHeadDot){ cosf(theta) * rad * 0.19f, y * 0.19f * 1.12f, sinf(theta) * rad * 0.19f, 0 };
    }
    _headDots[260] = (SGHeadDot){ -0.205f, 0.0f, 0.0f, 1 };
    _headDots[261] = (SGHeadDot){  0.205f, 0.0f, 0.0f, 1 };
    _headCount = 262;

    _maxSprites = _floorCount + _headCount + 4;
    _sprites = (SGMetalSprite *)calloc((size_t)_maxSprites, sizeof(SGMetalSprite));
    _depths = (float *)calloc((size_t)_maxSprites, sizeof(float));
    _order = (int *)calloc((size_t)_maxSprites, sizeof(int));

    _caption = [UILabel new];
    _caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _caption.textColor = [UIColor colorWithWhite:1.0 alpha:0.48];
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.numberOfLines = 2;
    [self addSubview:_caption];

    return self;
}

- (void)dealloc {
    free(_floorDots);
    free(_sprites);
    free(_depths);
    free(_order);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    if (self.window) {
        SGSpatialSetPreviewActive(YES);
        _lastTime = CACurrentMediaTime();
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else {
        SGSpatialSetPreviewActive(NO);
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

static inline void projectPoint3D(float x, float y, float z, float pitch, float fov, float cx, float cy,
                                  float *sx, float *sy, float *depthOut, float *perspOut) {
    float cp = cosf(pitch), sp = sinf(pitch);
    float ry = y * cp - z * sp;
    float rz = y * sp + z * cp;
    float camZ = 2.55f + rz;
    if (camZ < 0.2f) camZ = 0.2f;
    float persp = fov / camZ;
    *sx = cx + x * persp;
    *sy = cy - ry * persp;
    *depthOut = camZ;
    *perspOut = persp;
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    float dt = (float)(now - _lastTime);
    _lastTime = now;
    if (dt <= 0.0f || dt > 0.1f) dt = 1.0f / 60.0f;
    _clock += dt;

    BOOL enabled = SGSpatialVoiceEnabled();
    BOOL tracking = SGSpatialHeadTrackingConnected();
    float distSetting = (float)SGInt(SGKeySpatialVoiceDistance, 100) / 100.0f; // 0..2
    float roomSetting = (float)SGInt(SGKeySpatialVoiceRoom, 40) / 100.0f;      // 0..2
    NSInteger backIdx = SGInt(SGKeySpatialVoiceBack, 2);                       // 0=Never, 1=Slow, 2=Normal, 3=Fast
    float widthSetting = (float)SGInt(SGKeySpatialVoiceWidth, 100) / 100.0f;   // 0..1.5

    float recenterTau = 0.0f;
    if (backIdx == 1) recenterTau = 6.0f;
    else if (backIdx == 2) recenterTau = 3.0f;
    else if (backIdx == 3) recenterTau = 1.1f;

    if (tracking) {
        float liveYaw = SGSpatialVoiceRelativeYaw() * (180.0f / (float)M_PI);
        _headYaw += (liveYaw - _headYaw) * fminf(1.0f, dt * 14.0f);
        _voiceYaw = 0.0f;
    } else {
        // Exact Chroma 0.51.0 demo schedule: 0° -> -55° -> 0° -> +50°
        static const float kDemoAngles[4] = { 0.0f, -55.0f, 0.0f, 50.0f };
        if (_clock >= _nextDemoSwitch) {
            _demoIndex = (_demoIndex + 1) & 3;
            _headTarget = kDemoAngles[_demoIndex];
            _nextDemoSwitch = _clock + ((_headTarget == 0.0f) ? 2.4 : 3.1);
        }
        float accel = (_headTarget - _headYaw) * 18.0f - _headVel * 7.2f;
        _headVel += accel * dt;
        _headYaw += _headVel * dt;

        if (!enabled) {
            _voiceYaw = _headYaw;
        } else if (recenterTau > 0.0f) {
            float alpha = 1.0f - expf(-dt / recenterTau);
            _voiceYaw += (_headYaw - _voiceYaw) * alpha;
        } else {
            _voiceYaw = 0.0f;
        }
    }

    float liveVocal = SGSingLiveVocalPeak();
    float simVocal = 0.42f + 0.35f * sinf((float)_clock * 3.2f) + 0.20f * sinf((float)_clock * 7.1f + 0.8f);
    float targetVocal = fmaxf(liveVocal, fmaxf(0.15f, simVocal));
    _voiceLevel += (targetVocal - _voiceLevel) * fminf(1.0f, dt * 10.0f);

    float relDeg = enabled ? (_voiceYaw - _headYaw) : 0.0f;
    if (!enabled) {
        _caption.text = @"Off — voice turns with your head";
    } else if (tracking) {
        int deg = (int)lrintf(fabsf(relDeg));
        if (deg < 5) {
            _caption.text = @"Voice in front of you";
        } else if (relDeg < 0) {
            _caption.text = [NSString stringWithFormat:@"Voice %d° to your left", deg];
        } else {
            _caption.text = [NSString stringWithFormat:@"Voice %d° to your right", deg];
        }
    } else {
        _caption.text = @"Preview. With Sing on and AirPods in, it follows your head";
    }

    [self renderStageWithDistance:distSetting room:roomSetting width:widthSetting enabled:enabled];
}

- (void)renderStageWithDistance:(float)distance room:(float)room width:(float)width enabled:(BOOL)enabled {
    if (!_pipeline || !_queue) return;
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
    if (!drawable) return;

    CGFloat scale = metalLayer.contentsScale;
    float W = (float)metalLayer.drawableSize.width;
    float H = (float)metalLayer.drawableSize.height;
    if (W <= 10.0f || H <= 10.0f) return;

    float cx = W * 0.5f;
    float cy = H * 0.50f;
    float fov = fminf(W, H) * 0.88f;
    float pitch = 0.50f;

    float headRad = _headYaw * ((float)M_PI / 180.0f);
    float voiceRad = (enabled ? _voiceYaw : _headYaw) * ((float)M_PI / 180.0f);
    float orbDist = (distance - 1.0f) * 0.30f + 0.80f;
    float orbX = sinf(voiceRad) * orbDist;
    float orbZ = -cosf(voiceRad) * orbDist;

    int count = 0;

    // 1. Floor wave dots (20 concentric rings around head at y = -0.415)
    float floorY = -0.415f;
    for (int i = 0; i < _floorCount; i++) {
        SGFloorDot fd = _floorDots[i];
        float dx = fd.x - orbX;
        float dz = fd.z - orbZ;
        float dOrb = sqrtf(dx * dx + dz * dz);
        float ripple = sinf(fd.r * 9.5f - (float)_clock * 4.2f) * (0.012f + 0.018f * room) * _voiceLevel;
        float orbWave = expf(-dOrb * 2.2f) * sinf(dOrb * 12.0f - (float)_clock * 5.5f) * 0.025f * _voiceLevel;
        float y = floorY + ripple + orbWave;

        float sx, sy, depth, persp;
        projectPoint3D(fd.x, y, fd.z, pitch, fov, cx, cy, &sx, &sy, &depth, &persp);

        float ringFade = fmaxf(0.0f, 1.0f - (fd.r - 0.32f) / 2.25f);
        float sideGlow = fabsf(sinf(fd.angle - headRad)) * fminf(1.2f, width * 0.75f);
        float orbProx = expf(-dOrb * 2.4f) * (0.45f + 0.55f * _voiceLevel);
        float roomGlow = room * 0.22f * (0.5f + 0.5f * sinf(fd.r * 7.0f - (float)_clock * 3.5f));

        float alpha = (0.10f + 0.22f * ringFade + 0.18f * sideGlow + 0.42f * orbProx + roomGlow) * (0.55f + 0.45f * ringFade);
        alpha = fminf(0.92f, fmaxf(0.04f, alpha));

        float greenMix = fminf(1.0f, orbProx * 1.35f + roomGlow * 0.65f);
        float rCol = (1.0f - greenMix) * 1.0f + greenMix * 0.118f;
        float gCol = (1.0f - greenMix) * 1.0f + greenMix * 0.843f;
        float bCol = (1.0f - greenMix) * 1.0f + greenMix * 0.376f;

        float radPx = fmaxf(1.1f * (float)scale, (1.55f + 1.15f * orbProx) * (persp / fov) * (float)scale);
        _sprites[count] = (SGMetalSprite){
            .center = { sx, sy },
            .radius = radPx,
            .kind = 0.0f,
            .color = { rCol * alpha, gCol * alpha, bCol * alpha, alpha }
        };
        _depths[count] = depth;
        _order[count] = count;
        count++;
    }

    // 2. 3D Fibonacci sphere head at (0, -0.415, 0) rotated by headRad
    float ch = cosf(headRad), sh = sinf(headRad);
    for (int i = 0; i < _headCount; i++) {
        SGHeadDot hd = _headDots[i];
        float rx = hd.x * ch + hd.z * sh;
        float rz = -hd.x * sh + hd.z * ch;
        float wy = floorY + hd.y;

        float sx, sy, depth, persp;
        projectPoint3D(rx, wy, rz, pitch, fov, cx, cy, &sx, &sy, &depth, &persp);

        float facing = fmaxf(0.0f, -rz / 0.19f);
        float alpha = hd.isEar ? 0.88f : (0.18f + 0.48f * (0.5f + 0.5f * (hd.y / 0.21f)) + 0.22f * facing);
        float radPx = (hd.isEar ? 3.4f : 1.75f) * (persp / fov) * (float)scale;

        _sprites[count] = (SGMetalSprite){
            .center = { sx, sy },
            .radius = radPx,
            .kind = 0.0f,
            .color = { alpha, alpha, alpha, alpha }
        };
        _depths[count] = depth;
        _order[count] = count;
        count++;
    }

    // 3. Glowing Vocal Orb at (orbX, floorY + 0.04, orbZ) with kind = 1.0 + _voiceLevel
    {
        float sx, sy, depth, persp;
        projectPoint3D(orbX, floorY + 0.04f, orbZ, pitch, fov, cx, cy, &sx, &sy, &depth, &persp);
        float radPx = (28.0f + 14.0f * _voiceLevel) * (persp / fov) * (float)scale;
        float a = enabled ? 0.96f : 0.55f;
        float rCol = enabled ? 0.118f : 0.75f;
        float gCol = enabled ? 0.843f : 0.78f;
        float bCol = enabled ? 0.376f : 0.82f;
        _sprites[count] = (SGMetalSprite){
            .center = { sx, sy },
            .radius = radPx,
            .kind = 1.0f + _voiceLevel,
            .color = { rCol, gCol, bCol, a }
        };
        _depths[count] = depth - 0.05f;
        _order[count] = count;
        count++;
    }

    // Back-to-front depth sort (insertion sort on indices)
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

    id<MTLBuffer> spriteBuf = [_device newBufferWithLength:(NSUInteger)count * sizeof(SGMetalSprite)
                                                   options:MTLResourceStorageModeShared];
    SGMetalSprite *dst = (SGMetalSprite *)spriteBuf.contents;
    for (int i = 0; i < count; i++) {
        dst[i] = _sprites[_order[i]];
    }

    SGMetalFrame frameUni = { .size = { W, H }, .pixel = (float)scale, .pad = 0.0f };

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

#pragma mark - Settings Pages (1:1 Chroma 0.51.0 Layout)

UIViewController *SGSingSettingsPage(void) {
    SGRSingDemo *demo = [[SGRSingDemo alloc] initWithFrame:CGRectMake(0, 0, 320, 196)];
    SGModRow *demoRow = SGCustomViewRow(demo, 196.0);

    SGModRow *enableRow = SGSwitchRow(@"Sing", nil, SGKeySing);
    enableRow.glows = YES;
    enableRow.changed = ^(BOOL on) {
        if (!on) SGSetSingActive(NO);
        SGSingNotifySettingsChanged();
    };

    SGModRow *modelRow = SGChoiceRow(@"Voice model", nil, SGKeySingLight, @[@"Full model", @"Light model"], 0);
    modelRow.choiceNotes = @[
        @"The full model: cleanest vocal & instrument separation, runs locally on this iPhone",
        @"The light model, for older iPhones: lower CPU & battery usage"
    ];
    modelRow.chosen = ^(NSInteger idx) { SGSingNotifySettingsChanged(); };

    SGModRow *heatRow = SGOptionRow(@"Ignore heat warnings", nil, SGKeySingIgnoreHeat);
    SGModRow *memRow = SGOptionRow(@"Ignore memory warnings", nil, SGKeySingIgnoreMemory);

    NSArray<SGModSection *> *sections = @[
        SGSection(nil, @[demoRow]),
        SGNotedSection(nil, @[enableRow, modelRow], @"Turns the song's vocals down to sing over, or its instruments down to leave only the vocals, from the microphone in the lyrics and player."),
        SGSection(@"Limits", @[heatRow, memRow]),
    ];
    return [[SGModPage alloc] initWithTitle:@"Sing" intro:nil sections:sections footer:nil];
}

UIViewController *SGSpatialVoiceSettingsPage(void) {
    SGRSpatialVoiceScene *scene = [[SGRSpatialVoiceScene alloc] initWithFrame:CGRectMake(0, 0, 320, 340)];
    SGModRow *sceneRow = SGCustomViewRow(scene, 340.0);

    BOOL (^spatialOn)(void) = ^BOOL { return SGSpatialVoiceEnabled(); };

    SGModRow *spatialSwitch = SGSwitchRow(@"Spatial voice", @"Keeps the voice in one place as you turn your head", SGKeySpatialVoice);
    spatialSwitch.glows = YES;
    spatialSwitch.changed = ^(BOOL on) {
        if (on && !SGSingEnabled()) SGSetEnabled(SGKeySing, YES);
        SGSingNotifySettingsChanged();
    };

    SGModRow *distRow = SGSliderRow(@"Distance", nil, 0, 200, 5,
        ^double { return (double)SGInt(SGKeySpatialVoiceDistance, 100); },
        ^(double val) { SGSetInt(SGKeySpatialVoiceDistance, (NSInteger)llround(val)); SGSingNotifySettingsChanged(); },
        ^NSString *(double val) {
            NSInteger v = (NSInteger)llround(val);
            if (v <= 10) return @"Close";
            if (v == 100) return @"Default";
            if (v >= 190) return @"Far";
            return [NSString stringWithFormat:@"%ld%%", (long)v];
        });
    distRow.visible = spatialOn;

    SGModRow *roomRow = SGSliderRow(@"Room", nil, 0, 200, 5,
        ^double { return (double)SGInt(SGKeySpatialVoiceRoom, 40); },
        ^(double val) { SGSetInt(SGKeySpatialVoiceRoom, (NSInteger)llround(val)); SGSingNotifySettingsChanged(); },
        ^NSString *(double val) {
            NSInteger v = (NSInteger)llround(val);
            if (v <= 5) return @"Dry";
            if (v >= 190) return @"Wide";
            return [NSString stringWithFormat:@"%ld%%", (long)v];
        });
    roomRow.visible = spatialOn;

    SGModRow *backRow = SGChoiceRow(@"Back in front", nil, SGKeySpatialVoiceBack,
                                    @[@"Never", @"Slow", @"Normal", @"Fast"], 2);
    backRow.choiceNotes = @[
        @"Stays where it was until you recenter",
        @"Drifts back in front of you over ~6 seconds",
        @"Drifts back in front of you over ~3 seconds",
        @"Drifts back in front of you in ~1 second"
    ];
    backRow.chosen = ^(NSInteger idx) { SGSingNotifySettingsChanged(); };
    backRow.visible = spatialOn;

    SGModRow *widthRow = SGSliderRow(@"Instruments width", nil, 0, 150, 5,
        ^double { return (double)SGInt(SGKeySpatialVoiceWidth, 100); },
        ^(double val) { SGSetInt(SGKeySpatialVoiceWidth, (NSInteger)llround(val)); SGSingNotifySettingsChanged(); },
        ^NSString *(double val) {
            NSInteger v = (NSInteger)llround(val);
            if (v <= 5) return @"Mono";
            if (v == 100) return @"Default";
            if (v >= 145) return @"Wide";
            return [NSString stringWithFormat:@"%ld%%", (long)v];
        });
    widthRow.visible = spatialOn;

    NSArray<SGModSection *> *sections = @[
        SGSection(nil, @[sceneRow]),
        SGNotedSection(nil, @[spatialSwitch], @"Spatial voice places the song's vocals in front of you and tracks your head with AirPods Pro, AirPods Max, or Beats."),
        SGSection(@"Sound", @[distRow, roomRow, backRow, widthRow]),
    ];
    return [[SGModPage alloc] initWithTitle:@"Spatial voice" intro:nil sections:sections footer:nil];
}
