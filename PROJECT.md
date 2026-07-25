# Project: GG Music Player Enhancements

## Architecture
- **Frontend**: Flutter application (`/home/kriskata/Projects/gg`).
- **Backend**: Python FastAPI server (`/home/kriskata/Projects/gg_backend`).
- **Audio Pipeline**: Custom local `just_audio_media_kit` bindings pointing to `libmpv` (Linux) with FFmpeg audio filter support.
- **Queue System**: Manual Dart-level queue state machine avoiding `ConcatenatingAudioSource` to prevent native crashes.
- **EQ System**: Parametric band equalizer using FFmpeg's `eqband` filter on libmpv.

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Custom Platform Binding & EQ Core | Copy `just_audio_media_kit` files locally, expose `setProperty` to the private player context, implement `EQController` and `eqband` filter string generator. | None | DONE |
| 2 | Volume & Playback Controls | Add volume slider, implement `QueueController` with loop (off, all, one) and shuffle modes at the Dart level. | M1 | DONE |
| 3 | Real-time EQ UI | Implement EQ UI with 10-band sliders and presets (Pop, Rock, Bass Boost, Flat) in the Flutter frontend, connected to the audio filter. | M1 | DONE |
| 4 | Unit & Widget Tests | Write unit tests for `QueueController` and `EQController` and widget tests for player controls. Fix broken counter smoke test. | M2, M3 | DONE |
| 5 | Linux Build & E2E Validation | Build for Linux and verify that 100% of the unit/widget test suite passes. | M4 | DONE |

## Interface Contracts
### Player Platform ↔ Audio Engine
- `CustomJustAudioMediaKit.activePlayers`: static map of active native players.
- `MediaKitPlayer.setAudioFilter(String filter)`: sets the `af` property in mpv to apply real-time EQ filters.

### QueueController State
- `isShuffleEnabled`: bool
- `loopMode`: CustomLoopMode (off, all, one)
- `activeIndex`: int
- `activeQueue`: List<Song>
- `skipNext()`: advances playhead based on shuffle/loop.
- `skipPrevious()`: goes back or restarts song.
- `toggleShuffle(bool)`: permutes remaining items or restores original queue.
- `setLoopMode(CustomLoopMode)`: updates looping behavior.

### EQController State
- `gains`: List<double> (10 bands: 31.25Hz to 16kHz, clamped to [-10.0, 10.0] dB).
- `applyPreset(EQPreset)`: updates gains.
- `buildFilterString()`: generates FFmpeg `eqband` chain.

## Code Layout
- `lib/player/custom_just_audio_media_kit.dart`: Local package copy to track active players.
- `lib/player/mediakit_player.dart`: Exposes libmpv `setProperty` FFI.
- `lib/player/queue_controller.dart`: State machine for play queue.
- `lib/player/eq_controller.dart`: State machine and FFmpeg filter builder.
- `lib/widgets/eq_sheet.dart`: UI for EQ adjustment and presets.
- `lib/main.dart`: UI with volume slider, queue controls, and custom player initialization.
- `test/queue_controller_test.dart`: Unit tests for Queue logic.
- `test/eq_controller_test.dart`: Unit tests for EQ logic.
- `test/widget_test.dart`: Fixed widget smoke test.
