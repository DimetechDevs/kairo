# Kairo

Kairo is an Android-first anime discovery and playback app built with Flutter.

- Browse and search anime (catalogue data from AniList)
- Keep a personal list: watching, planned, completed, paused, dropped
- Import your own video files and play them offline
- Accounts are optional; everything works on the phone first

## Getting started

```sh
flutter pub get
flutter run        # with an Android device or emulator connected
flutter test
```

## Project layout

```
lib/
  app/        router (go_router) and the five-tab shell
  core/       theme: colours, spacing, radii, fonts
  data/       models, mock data and Riverpod providers
  features/   one folder per screen: home, discover, details, my_anime, library, profile, player
  widgets/    shared UI: cover art, poster cards, pills, empty states
```

## Status

The screens run on mock data. Next steps: AniList catalogue and a SQLite watchlist, then real file import and video playback.
