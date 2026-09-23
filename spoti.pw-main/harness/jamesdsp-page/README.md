# Audio effects page harness

Mod Settings > Audio effects (`tweak/Sources/Shared/JamesDSP/`) in a navigation controller, the way Mod
Settings pushes it: the real page, curve and file pages, the real `Settings/` framework and
`JamesDSPSettings.m`, with `stubs.m` standing in for the engine (a made-up status that changes every three
seconds, fake libraries in the app's temporary directory, a smooth curve through the gains instead of the
filter's response, and an error for any chosen file with "broken" in its name).

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/JamesDSPHarness.app
    xcrun simctl launch <udid> com.vojta.jamesdspharness master allon section=4 drag=9:7.5
    xcrun simctl io <udid> screenshot shot.png

Other agents use the simulator too: make a device of your own (`xcrun simctl create`) and address it by
UDID. Every launch clears the `spotifyglass.dsp` keys first unless `keep` is on the line; `main.m` lists the
setup words (`master`, `allon`, `broken`, `slow`) and the actions, played one every 0.7 s from 1 s in:
scrolling to a card, flipping a card's switch, a band mid-drag and let go, a preset, a tap on a row, the
file and GraphicEQ pages, an import through the document picker's delegate, Paste, a slider moved, VoiceOver's
swipe on a slider or a band, the reset's alert confirmed, and `dump`, which logs the stored keys:

    xcrun simctl spawn <udid> log show --last 1m --predicate 'process == "JamesDSPHarness"' | grep '\[harness\]'

2026-09-18, iPhone 17 Pro (402pt) and iPhone 13 mini (375pt) on iOS 26.5: every card laid out with all
effects on, the fifteen band labels apart at 375pt, a preset morphing the curve with the handles (`slow`),
long choice names moving under the title, the animated opening of a card and an error row turning up on
the once a second tick; the values stored under the right keys, snapped to their steps.

What it does not cover: a real finger. The drag is played through the curve's own methods, so whether its
pan wins over the table's scroll when a finger starts on a handle (and loses anywhere else) is untested
here; `hit` logs which band a finger going down at and around each handle would take. Nor the document
picker's own UI, the pull-down menu of presets open, or Spotify's fonts, which the page adopts on the phone.
