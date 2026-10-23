#import <UIKit/UIKit.h>

#define SGKeyAutoMix            @"spotifyglass.automix"
#define SGKeyAutoMixStyle       @"spotifyglass.automix.style"
#define SGKeyAutoMixLength      @"spotifyglass.automix.length"
#define SGKeyAutoMixPlaylists   @"spotifyglass.automix.playlists"
#define SGKeyAutoMixLikedSongs  @"spotifyglass.automix.likedsongs"
#define SGKeyAutoMixAlbums      @"spotifyglass.automix.albums"
#define SGKeyAutoMixRadio       @"spotifyglass.automix.radio"
#define SGKeyAutoMixQueue       @"spotifyglass.automix.queue"
#define SGKeyAutoMixAutoplay    @"spotifyglass.automix.autoplay"
#define SGKeyAutoMixInfo        @"spotifyglass.automix.info"

BOOL SGAutoMixEnabled(void);
NSString *SGAutoMixSummary(void);
NSString *SGAutoMixCurrentStatusText(void);
UIViewController *SGAutoMixSettingsPage(void);
