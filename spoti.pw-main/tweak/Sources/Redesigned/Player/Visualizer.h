#import <UIKit/UIKit.h>

#define SGRKeyVisualizer          @"spotifyglass.redesign.player.visualizer"
#define SGRKeyVisualizerShader    @"spotifyglass.redesign.player.visualizer.shader"
#define SGRKeyVisualizerCustom    @"spotifyglass.redesign.player.visualizer.custom"
#define SGRKeyVisualizerStyle     @"spotifyglass.redesign.player.visualizer.style"
#define SGRKeyVisualizerAudio     @"spotifyglass.redesign.player.visualizer.audio"
#define SGRKeyVisualizerDim       @"spotifyglass.redesign.player.visualizer.dim"
#define SGRKeyVisualizerSpeed     @"spotifyglass.redesign.player.visualizer.speed"

#define SGRKeyFluidSpeed          @"spotifyglass.redesign.player.fluid.speed"
#define SGRKeyFluidWarp           @"spotifyglass.redesign.player.fluid.warp"
#define SGRKeyFluidBlur           @"spotifyglass.redesign.player.fluid.blur"
#define SGRKeyFluidSaturation     @"spotifyglass.redesign.player.fluid.saturation"
#define SGRKeyFluidBrightness     @"spotifyglass.redesign.player.fluid.brightness"

#define SGRKeyPlayerVolume        @"spotifyglass.redesign.player.volume"
#define SGRKeyPlayerLandscape     @"spotifyglass.redesign.player.landscape"
#define SGRKeyPlayerLandscapeArt  @"spotifyglass.redesign.player.landscape.art"
#define SGRKeyAccentFollows       @"spotifyglass.redesign.accent.playing"

#define SGRKeyMiniPlayer          @"spotifyglass.redesign.miniplayer"
#define SGRKeyBarSwap             @"spotifyglass.redesign.bar.swap"
#define SGRKeyAlbumMotion         @"spotifyglass.redesign.album.motion"
#define SGRKeyArtistLogo          @"spotifyglass.redesign.artist.logo"

#define SGRKeyLyricsSize          @"spotifyglass.redesign.lyrics.size"
#define SGRKeyLyricsDimNear       @"spotifyglass.redesign.lyrics.dim.near"
#define SGRKeyLyricsDimFar        @"spotifyglass.redesign.lyrics.dim.far"
#define SGRKeyLyricsBlur          @"spotifyglass.redesign.lyrics.blur"
#define SGRKeyLyricsLift          @"spotifyglass.redesign.lyrics.lift"
#define SGRKeyLyricsGlow          @"spotifyglass.redesign.lyrics.glow"

UIViewController *SGRVisualizerSettingsPage(void);
UIViewController *SGRFluidArtworkSettingsPage(void);
UIViewController *SGRLyricsStyleSettingsPage(void);
UIViewController *SGRHomeSettingsPage(void);
UIViewController *SGRAlbumsSettingsPage(void);
UIViewController *SGRArtistsSettingsPage(void);
NSString *SGRVisualizerSummary(void);
