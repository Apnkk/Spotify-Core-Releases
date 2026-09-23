# libjamesdsp

The effects engine of JamesDSP (James Fung), as JamesDSP for Linux and RootlessJamesDSP build it, run by
`tweak/Sources/Shared/JamesDSP/SGDSPEngine.m` on Spotify's output. GPLv2 (`LICENSE`, also
`subtree/Main/LICENSE`); spoti.pw is GPLv3 and ships it the way JDSP4Linux and RootlessJamesDSP do.

## Where it comes from

- `subtree/` and the three files beside it (`JdspImpResToolbox`, `EELStdOutExtension`,
  `PrintfStdOutExtension`, `.c` and `.h`): [Audio4Linux/JDSP4Linux](https://github.com/Audio4Linux/JDSP4Linux)
  at `eb848bf507325ecbe765569d37c163d3b7c6fd11`, its `libjamesdsp/` directory. `subtree/` is JDSP4Linux's
  git subtree of [ThePBone/JamesDSPManager](https://github.com/ThePBone/JamesDSPManager) (branch
  `extensions`, a fork of james34602/JamesDSPManager), kept at the same paths so a diff against either
  reads straight. Only `subtree/Main/LICENSE` and `subtree/Main/libjamesdsp/jni/jamesdsp/{jdsp/, cpthread.h}`
  are carried; the Android effect around them (`jamesdsp.c`, `Android.mk`...) and the other apps are not.
- `assets/Liveprog/*.eel` (40 scripts) and `assets/DDC/*.vdc` (3 presets):
  [timschneeb/RootlessJamesDSP](https://github.com/timschneeb/RootlessJamesDSP) at
  `60d25ae8a53c6f4691c090673df290a73c6b6357`, `app/src/main/assets/` (GPLv3). Its convolver samples
  (7 MB of WAV) are not carried.
- Ours: `Makefile`, `embed-assets.pl` and `JdspBundledFiles.h`, which compile `assets/` into the library as
  a table (`jdspBundledFiles`) the tweak installs into its file libraries.

## Local changes

Every one is marked `spoti.pw:` where it is.

- `subtree/.../generalDSP/TwoStageFFTConvolver.h`: `THREAD` is no longer defined. With it every long
  convolution (the convolver's responses, crossfeed's surround) had a worker thread of normal priority
  for its tail, and the render thread took a mutex to hand it work and could wait on a condition variable
  for it. The file's own single-threaded path does the tail inline instead: on the Mac Church.wav (4
  channels, 10 s) costs 0.2 ms a 1024-frame block on average and 2.8 ms at the worst block.
- `subtree/.../jdspController.c`, `JamesDSPInit`: the processing mutex is recursive.
  `JamesDSPSetSampleRate` holds it while its forced refresh calls `CrossfeedEnable`,
  `ArbitraryResponseEqualizerEnable` and `StereoEnhancementRefresh`, which take it again, so the first
  sample rate change deadlocked.
- `subtree/.../generalDSP/spectralInterpolatorFloat.c`, `InitSpectralInterpolator`: one more level
  allocated (the grid's end); the slopes read one past the array (AddressSanitizer, on every compander
  setting).
- `JdspImpResToolbox.c`, `ReadImpulseResponseToFloat`: the channel and frame counts start at zero and a
  file that did not load returns before they are read (they were read unset, and a NULL buffer split);
  RootlessJamesDSP's check of the advanced waveform settings (a shift past the buffer falls back to the
  defaults instead of writing out of bounds); a mono response in "minimum phase and shrink" no longer
  writes `th[-1]`; the extension is compared in any case.
- `PrintfStdOutExtension.c`: `printf` and `__android_log_print` format into a buffer on the stack instead
  of `vasprintf`/`asprintf` (no allocation when a message is printed while audio is processed), and
  `__android_log_print` formats its arguments (it passed the format string on as it was).
  `PrintfStdOutExtension.h`: its include guard was `EELSTDOUTEXTENSION_H`, the same as
  `EELStdOutExtension.h`'s, so one hid the other.

## Building

`make [JDSP_PLATFORM=ios|sim|mac] [JDSP_SANITIZE=address|thread]` builds `build/<platform>/libjamesdsp.a`
(gitignored) with JDSP4Linux's flags (`-std=gnu11 -O2`, `printf` routed to its handler, `CUSTOM_CMD` for
Liveprog's output), warnings off and every symbol hidden. It is incremental, rebuilds everything when the
flags change, and takes about 3 s from nothing. `tweak/Makefile` runs it for `ios` before the tweak links;
`harness/jamesdsp/` for the Mac and the simulator.

Guards against inputs that crash libjamesdsp's own parsers (a GraphicEQ string with an odd count of
numbers, a DDC file whose sections do not hold the numbers its first line promises) are in
`SGDSPEngine.m`, not here.
