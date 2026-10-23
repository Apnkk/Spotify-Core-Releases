#import <UIKit/UIKit.h>

#define SGKeySing               @"spotifyglass.redesign.sing"
#define SGKeySingIgnoreHeat     @"spotifyglass.redesign.sing.ignoreHeat"
#define SGKeySingIgnoreMemory   @"spotifyglass.redesign.sing.ignoreMemory"
#define SGKeySingLight          @"spotifyglass.redesign.sing.light"
#define SGKeySingVocalLevel     @"sing.vocalLevel"

#define SGKeySpatialVoice         @"spotifyglass.redesign.spatialVoice"
#define SGKeySpatialVoiceDistance @"spotifyglass.redesign.spatialVoice.distance"
#define SGKeySpatialVoiceRoom     @"spotifyglass.redesign.spatialVoice.room"
#define SGKeySpatialVoiceBack     @"spotifyglass.redesign.spatialVoice.back"
#define SGKeySpatialVoiceWidth    @"spotifyglass.redesign.spatialVoice.width"

BOOL SGSingEnabled(void);
BOOL SGSingActive(void);
void SGSetSingActive(BOOL active);

float SGSingVocalLevel(void);
void SGSetSingVocalLevel(float level);

BOOL SGSpatialVoiceEnabled(void);
void SGSingNotifySettingsChanged(void);

// Live telemetry for the Spatial Voice stage and Sing ring animations.
float SGSpatialVoiceRelativeYaw(void);
float SGSingLiveVocalPeak(void);
float SGSingLiveInstrumentPeak(void);

NSString *SGSingSummary(void);
NSString *SGSpatialVoiceSummary(void);

UIViewController *SGSingSettingsPage(void);
UIViewController *SGSpatialVoiceSettingsPage(void);
