Jamendo Music Player

Jamendo Music Player is a simple Flutter music player that searches and streams free music from Jamendo (Jamendo API v3).  
Designed as a dev-friendly, local-first app for Android and web testing (web playback via browser, Android playback via just_audio).

## Features
- Search Jamendo tracks by keyword (artist, track title, genre).
- Play tracks using `just_audio`.
- Build and manage a play queue.
- Shuffle queue support.
- "Play similar next" — enqueues a track by the same artist when the current track finishes or when requested.
- Simple, minimal UI for fast iteration.

## Quickstart

1. Clone repo and open in VS Code or Android Studio.
2. Ensure Flutter SDK is installed and your device/emulator is ready.
3. Add dependencies and fetch packages:
4. Edit `lib/main.dart` if you want to use a different Jamendo Client ID (the default is a public client id).
> **Do not** add Jamendo client secret to the app. Client secret must never be exposed in client apps.
5. Run (Android):
> flutter run -d <your-android-device-id>
Or run (web):
> flutter run -d edge
6. Build an installable APK:
> flutter build apk --debug
> adb install -r build/app/outputs/flutter-apk/app-debug.apk

## Notes & Limitations
- Jamendo catalog is independent — mainstream artists may not be available.
- The app uses the Jamendo public API (client id only). Check Jamendo's terms if you plan to publish.
- `just_audio` performs well on Android; desktop may need additional platform backends.
- This project is intentionally minimal and easy to extend. Add playlists, persistent storage, or improved similarity engines as needed.

## License
MIT — use it, fork it, ruin it, fix it, blame me later.

