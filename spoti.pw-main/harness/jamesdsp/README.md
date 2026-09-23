# JamesDSP harness

Two halves, both building libjamesdsp (`vendor/libjamesdsp`) for their platform first.

## The engine on the Mac (`main.m`)

`SGDSPEngine.m` as the tweak compiles it, over the Mac build of libjamesdsp. A song decoded with ExtAudioFile
goes through the engine in the slices iOS hands its output unit (1024, 4096, 470 and 471 in turn, 512, and a
mix down to single frames), and each check prints a line: bypass exact to the sample one block late, no
allocation on the render thread (malloc, calloc and realloc are the executable's own here, so libjamesdsp's
calls land in them), nothing not finite or over the limiter with every effect on, bass boost and equalizer
presets by band, every bundled Liveprog script and DDC preset, broken inputs refused with the file's line,
the convolver reproducing RootlessJamesDSP's Church.wav from an impulse, sample rate changes, a reset, a
thread changing settings while another processes, and what each effect costs. WAVs go to the out dir.

    ./build.sh && build/jamesdsp <song> <Church.wav> <out dir>
    ./build.sh thread && build/jamesdsp-thread <song> <Church.wav> <out dir> stress
    ./build.sh address && build/jamesdsp-address <song> <Church.wav> <out dir>

Church.wav is in RootlessJamesDSP's `app/src/main/assets/Convolver/`, not in this repo.

2026-09-18, M-series Mac: every check passes, and under ThreadSanitizer (no report) and AddressSanitizer
(which found the interpolator's overread, fixed in the vendored copy). A 1024-frame block at 48 kHz (21.3 ms
of sound) costs under 0.01 ms with every effect off and about 1 ms with every effect on (4.8% of real time,
about 3 ms at the worst block); the convolver with Church.wav 0.2 ms, 2.2 to 2.8 ms at the worst, its tail
being convolved inline. None of the 43 bundled files allocates while processing. A change of setting every
30 ms leaves 2 to 3% of the blocks dry, at most 4 in a row (85 ms); the convolver's load holds the lock
longest (17 to 44 ms, with other work on the machine).

## The hook in the simulator (`sim/main.m`)

Spotify's chain rebuilt with real units (a converter fed by a render callback, a mixer, RemoteIO, wired with
MakeConnection), with `JamesDSP.x` (logos, internal generator), its settings and libraries and the engine
compiled into an app whose main executable is the harness, so its `AudioOutputUnitStart` goes through the
rebound import slot as Spotify's does. A second render notify, added after the output started and so after
JamesDSP's, measures what JamesDSP left in the buffer while a script flips settings: the switch off and a
gain that must not apply, the switch on and -15 dB, a Liveprog script from the library swapping the
channels, a reverb ringing out after the source stops (the silence flag cleared), a file missing from the
library and its error, then a 16-bit interleaved client at 48 kHz.

    THEOS=$HOME/theos ./build-sim.sh
    xcrun simctl install <udid> build/sim/JamesDSPHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.jamesdspharness

Use a device of your own (`xcrun simctl create`), by UDID. The tweak's own lines are in the unified log:
`xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "[spotifyglass]"'`.

2026-09-18: every step passes. It also showed that the notify's buffers are in the RemoteIO unit's output
format (the hardware's: 48 kHz float, a buffer per channel), not the client format Spotify sets on its input
(44.1 kHz, or 16-bit interleaved), so the engine reads the output scope and runs at the hardware's rate.
