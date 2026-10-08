# Spotify Lifetime & spoti.pw Combined Edition

Unified project containing both **Spotify Lifetime Edition** (Premium features, hardened anti-ad engine, lyrics providers) and **spoti.pw** (Liquid Glass iOS UI redesign).

## Features
- **Spotify Lifetime**: True Premium experience (unlimited skips, extreme audio quality, on-demand playback, lyrics offline/synced).
- **Hardened Anti-Ad Engine**:
  - Full RemoteConfig & ProductState spoofing (`ads=0`, zero audio/video ad frequencies).
  - Suppression of modern Swift ad services (`RealTimeAdControllerServiceImpl`, `EmbeddedPlaylistServiceImpl`, `EmbeddedCTAElementsServiceImpl`, etc.).
  - Blocked ad telemetry and real-time ad network requests.
  - 0ms instant ad auto-skipper fallback in audio queue.
- **spoti.pw**: UIGlassEffect iOS redesign, Live Activity, custom gestures, audio effects (DSP).
- **Custom Credits**: Modified by Ares — Spotify Lifetime Edition.

## Structure
- `EeveeSpotifyReincarnated-Master/`: Spotify Lifetime tweak source code with custom credits and hardened ad-blocking.
- `spoti.pw-main/`: spoti.pw tweak source code with custom credits and real-time ad skipper.
