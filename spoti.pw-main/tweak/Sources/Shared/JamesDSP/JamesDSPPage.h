// Mod Settings > Audio effects: JamesDSP's switch with what the engine is doing under it, then a card per
// effect in RootlessJamesDSP's order, each opening out into its controls while its switch is on. Everything
// on it goes through JamesDSP.h's setters, so it applies as it changes, a slider while it is dragged.
//
//     JamesDSPPage.m          the page: the switch, the status, the effects' cards, their sliders and choices
//     SGDSPCurveView.m        the equalizer's and the compressor's curve, with a handle to drag per band
//     JamesDSPLibraryPage.m   a file effect's library (the convolver's, ViPER DDC's, Liveprog's) and the GraphicEQ editor
//
// Main thread only.
#import <UIKit/UIKit.h>
#import "JamesDSP.h"

UIViewController *SGDSPSettingsPage(void);
// What the Mod Settings row reads out: Off, On, or how many effects are on.
NSString *SGDSPSummary(void);

// The pages the effects' rows push (JamesDSPLibraryPage.m).
UIViewController *SGDSPLibraryPage(SGDSPFileKind kind);
UIViewController *SGDSPGraphicEqPage(void);
// The choice of a file effect's library, "None" when there is none.
NSString *SGDSPChosenFile(SGDSPFileKind kind);
