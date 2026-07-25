# GG Project

## Architecture
- **Frontend**: Flutter (supports Linux and Web).
- **Backend**: Python FastAPI server (located in `~/gg_backend`).
- **Communication**: The frontend fetches song metadata and streams audio via a REST API.

## Core Features
- **Dynamic Library**: The backend scans its `audio_files/` directory in real-time using `tinytag`.
- **Drag & Drop**: Users can drop MP3 files onto the app window to upload them to the backend.
- **Side Panel**: Displays large album art and song lyrics.
- **Multi-platform Playback**: Uses `just_audio` with the `media_kit` (mpv) backend for robust Linux support.

## Conventions
- **Audio Loading**: On Linux, avoid `ConcatenatingAudioSource`. Use `_player.setUrl()` for individual tracks and handle queueing manually to prevent native crashes.
- **Preloading**: Set `preload: false` when setting the audio source to prevent UI hangs on some Linux environments.
- **Encoding**: Filenames in URLs are URL-encoded by the backend to support special characters (Cyrillic, spaces, etc.).

## Setup & Run
### Backend
```bash
cd ~/gg_backend
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```
### Frontend
```bash
cd ~/gg
flutter run -d linux
```
