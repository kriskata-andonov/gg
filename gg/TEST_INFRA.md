# GG Music Player Test Infrastructure Documentation

## Features Under Test

This test suite covers the following core logical features of the GG Music Player:
1. **Volume Control**: Verifying volume adjustment logic and correct interface/API integration with the player.
2. **Queue Management**: Verifying sequential navigation (`skipNext`/`skipPrevious`), boundary conditions, looping behaviors (off, single song, all songs), shuffle logic, and recovery of original queue states on disabling shuffle.
3. **Parametric EQ Control**: Verifying 10-band equalizer adjustments, gain bounds clamping, presets application, and correct FFmpeg/libmpv filter string compilation syntax.

---

## Test Architecture and Setup Details

The testing suite is designed around Flutter and Dart's unit and widget test frameworks:
- **Unit Tests**: Focus on pure business logic controllers (`QueueController` and `EQController`) separated from UI rendering to ensure fast execution and reliable assertions.
- **Widget (Smoke) Tests**: Verify correct layout rendering of the `MusicApp` shell without crashes, asserting the existence of critical widgets (e.g., the AppBar title and the search input field).
- **Mocking Strategy**: Since `just_audio` interacts with native FFI / player implementations which are unavailable in a pure test environment, a custom mocked backend is introduced:
  - `MockJustAudioPlatform` implements the abstract `JustAudioPlatform` interface.
  - `MockAudioPlayerPlatform` implements the abstract `AudioPlayerPlatform` interface.
  - Setup is registered inside `setUpAll` before rendering widget trees to bypass platform channel calls and avoid native crash loops.

---

## 4-Tier Test Coverage Strategy

Our testing hierarchy separates checks into four distinct layers to ensure thorough reliability:

### Tier 1: Feature Coverage (Core Functionality)
- Verifies default parameters on initialization (e.g., default index `0`, shuffle off, loop off, flat EQ).
- Assures basic sequential skipping updates the current active track index appropriately.
- Assures presets correctly modify all 10 band gains on the EQ controller.

### Tier 2: Boundary / Corner Cases
- Verifies that boundary operations do not wrap around when loop mode is disabled (`off`).
- Verifies that values out of range (e.g. gain values outside `[-10.0, 10.0]` dB) are clamped correctly to the boundary limit rather than throwing exceptions or allowing corrupt state.
- Assures that empty collections or edge selections don't crash the queue controller.

### Tier 3: Cross-Feature Combinations
- Tests interactions between different active modes, such as wrapping behaviors when loop-all is active while shuffle mode is also enabled.
- Assures original indices and track ordering are correctly restored after disabling shuffle regardless of sequential skips executed during the shuffled state.

### Tier 4: Real-World Workload Scenarios
- Tests application behavior during full-app widget mounting (smoke test).
- Simulates user search interactions, list populating, and player stream updates in mock mode.

---

## Test Execution Command

To execute the test suite, run the following command in the project root directory:

```bash
flutter test
```
