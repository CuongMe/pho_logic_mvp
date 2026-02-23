# Pho Logic

<div align="center">
  <img src="images/menu_logo.png" alt="Pho Logic logo" width="280" />
  <p><b>Vietnamese-themed Match-3 puzzle game built with Flutter and Flame.</b></p>
</div>

## Quick Links
- Play on Itch.io: https://cuongme.itch.io/ph-logic
- Privacy Policy: https://cuongme.github.io/pho_logic_mvp/
- Technical Documentation: https://cuongme.github.io/pho_logic_mvp/documentation.html

## About
Pho Logic is a cozy match-3 game inspired by Vietnamese food culture.
The core gameplay loop is:
swap -> match -> clear -> refill.

This project is focused on clean game architecture, responsive UI, and strong visual feedback.

## Gameplay Highlights
- Match 3 or more tiles to clear the board.
- Cascading matches create combo chains.
- Special power-ups add strategic depth.
- Fast level flow designed for short, replayable sessions.
- JSON-driven screen layout and positioning system.

## GIF Showcase
All gameplay GIF files from `gif/` are shown below.

| Blocker | Dragon Fly |
| --- | --- |
| <img src="gif/blocker.gif" alt="Blocker" width="280" /> | <img src="gif/dragon_fly.gif" alt="Dragon Fly" width="280" /> |

| Firecracker | Horizontal Party Popper |
| --- | --- |
| <img src="gif/firecracker.gif" alt="Firecracker" width="280" /> | <img src="gif/horizontal_party_popper.gif" alt="Horizontal Party Popper" width="280" /> |

| Sticky Rice Bomb | Vertical Party Popper |
| --- | --- |
| <img src="gif/sticky_rice_bomb.gif" alt="Sticky Rice Bomb" width="280" /> | <img src="gif/vertical_party_popper.gif" alt="Vertical Party Popper" width="280" /> |

## Tech Stack
- Flutter (Dart)
- Flame
- flame_audio
- audioplayers
- shared_preferences
- url_launcher

## Project Structure
```text
lib/                 Flutter app and game logic
assets/              Game assets (sprites, backgrounds, audio, JSON)
assets/json_design/  JSON-driven UI layouts
gif/                 Gameplay GIF previews
android/ ios/ web/   Platform targets
```

## Getting Started
### Prerequisites
- Flutter SDK installed
- Dart SDK available through Flutter
- Android SDK (for Android builds)

### Run
```bash
flutter pub get
flutter run
```

### Build
```bash
flutter build apk --release
flutter build appbundle --release
flutter build web --release
```

### Build Web ZIP (PowerShell)
```powershell
flutter build web --release
Compress-Archive -Path build\web\* -DestinationPath build\pho_logic_web_release.zip -Force
```

## Version
Current app version in `pubspec.yaml`: `1.0.0+6`.

## License
Copyright (c) 2026 Cuong Tran.
All rights reserved.
