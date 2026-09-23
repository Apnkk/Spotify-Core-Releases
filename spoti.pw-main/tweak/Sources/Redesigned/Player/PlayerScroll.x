// Player redesign: the player is one screen. Spotify's is a list with the player as its header and the
// cards under it, and the Music app's player does not scroll at all -- the lyrics arrive in the player
// itself (PlayerLyrics.x), from the footer's glyph, rather than from under it. Every card is collapsed
// already (PlayerCards.x), so all that is left below is the gaps the list leaves between them.
//
// The list is not switched off: the pull that dismisses the player rides on its own pan recogniser.
// -[SPTBarInteractivePresentationController scrollViewDidAppear:] takes the list's panGestureRecognizer,
// adds dismissPanWithGestureRecognizer: to it and makes its own dismiss recogniser wait for it to fail,
// and that handler starts the dismissal only while the list is at or above its top (Spotify 9.1.78,
// 0x109814898 and 0x109814400). Turning scrolling off takes that recogniser out with it and the player
// can no longer be swiped away.
//
// So the range is closed instead: the bottom inset is set to whatever makes the furthest the list can
// scroll its own top. A drag upward then only stretches and springs back, a drag downward still carries
// the offset below zero, and the dismissal is untouched. It is worked out again on every layout pass
// and on every scroll, since the cards arrive long after the player does and change the content's height.
//
// Tree (trees/clean/player/01.txt:20): UICollectionView 402x874 id=scrolling_npv_collection_view_accessibility_identifier,
// with the player as an Element_List.SupplementaryItemView the size of the screen and a cell per card
// under it. NPVScrollViewController is its delegate (:567).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static NSString *const kListIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
// Insets are never compared for equality, only for being a point or so out.
static const CGFloat kSlack = 0.5;

static char kListKey;

static void pinToTop(UIScrollView *list) {
    if (!list || list.bounds.size.height < 1) return;
    UIEdgeInsets own = list.contentInset, adjusted = list.adjustedContentInset;
    // What the safe area adds on top of the inset of its own, which has to be left in place.
    CGFloat safeArea = adjusted.bottom - own.bottom;
    CGFloat over = list.contentSize.height - list.bounds.size.height;
    // The furthest it may scroll is where it rests: -adjusted.top, its own top.
    CGFloat want = -adjusted.top - over - safeArea;
    if (want >= 0 || fabs(want - own.bottom) < kSlack) return;
    own.bottom = want;
    list.contentInset = own;

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: the list pinned to its top, %.0fpt of cards closed off", -want); });
}

%hook _TtC21NowPlaying_ScrollImpl23NPVScrollViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    UIView *list = SGRFindByIdentifier(page, kListIdentifier, &kListKey);
    if ([list isKindOfClass:UIScrollView.class]) pinToTop((UIScrollView *)list);
}

// A card arriving, or one of them settling on its height, grows the content without a pass of the page's.
- (void)collectionView:(UICollectionView *)list willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path {
    %orig;
    pinToTop(list);
    // The height a cell reports is asked for after this, so the last word on the content is a runloop away.
    dispatch_async(dispatch_get_main_queue(), ^{ pinToTop(list); });
}

- (void)scrollViewDidScroll:(UIScrollView *)list {
    pinToTop(list);
    %orig;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC21NowPlaying_ScrollImpl23NPVScrollViewController"]);
}
