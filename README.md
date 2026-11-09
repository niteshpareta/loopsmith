# Loopsmith

A 3D ring-untangle puzzle for Android and iOS, built with Flutter.

![Home, a level, a weekly knot, the daily screen, settings and the light theme in Spanish](docs/screens.png)

Turn each ring until its opening meets the link, slip it free, and land it on
the right peg. Rings that are not next on their peg wait in a four-slot tray;
a full tray ends the attempt.

A 29-second clip of the game playing itself is in
[`docs/gameplay.mp4`](docs/gameplay.mp4) (no sound; recorded from the web
build).

"Loopsmith" is a working title. Check store and trademark availability before
you publish under it.

## Run it

```bash
flutter pub get
```

```bash
flutter run
```

Built and tested with Flutter 3.47.9 (Dart 3.13.7). The bundle id is the
placeholder `com.yourstudio.loopsmith`; change it before you publish.

## What is in the box

| Area | What you get |
|---|---|
| Levels | 300 campaign levels, 90 daily knots and 56 weekly-run knots, every one proven solvable by the solver |
| Knots | Rings lean at different angles and come in four sizes; never more than nine rings in one knot |
| Ring types | Plain, twin (two openings), geared pairs, sealed rings, and fixed frames in three shapes (square, triangle, D) |
| Goals | Colour pegs in order, a four-slot holding tray, stars against par |
| Boosters | Hint (solver-driven), undo (first one free), extra tray slot |
| Screens | Home, play, level clear, tray full, daily knot with weekly run, workshop, settings, level list |
| Progress | Coins, stars, six ring skins, a collectible set, daily streak with savers, a seven-knot weekly run |
| Look | Lit, rounded tubes with gloss, metal, stone and neon finishes |
| Feel | 17 sound effects (8 recorded, 9 synthesised), three adaptive music layers, vibration, sparkles |
| Languages | English, Spanish, Portuguese, French, German; follows the phone or is chosen in settings |
| Reminders | Optional evening reminder on days you have not played; off until the player turns it on |
| Access | Light theme, colour-blind marks, left-handed layout, reduce motion, screen-reader labels |
| Money | Reward and between-level ads (AdMob), remove-ads and starter-kit purchases |
| Tests | 76 automated tests covering rules, solver, levels, tap accuracy, saves, streaks, weekly runs, reminders, translations, play flow and screens |

## How it is built

```
lib/
  game/       Rules, solver, level generator and tap-accuracy maths. Plain Dart.
  render/     The lit ring mesh, scene animation, touch, flights to pegs.
  screens/    Home, play, clear, daily, workshop, settings, level list.
  services/   Saves, audio, vibration, ads, store, reminders, analytics.
  l10n/       Text in five languages, one file per language.
  ui/         Buttons, panels and other shared widgets.
assets/
  levels/     campaign.json, daily.json and weekly.json (generated).
  audio/      Sound effects (WAV) and music loops (MP3). See CREDITS.txt.
  fonts/      Unbounded and Figtree (SIL Open Font License).
tool/
  make_levels.dart   Regenerates the level packs.
  make_audio.py      Regenerates every sound.
  make_icons.py      Regenerates app icons for every platform.
  cc0/               Recorded source sounds (CC0) used by make_audio.py.
```

### The 3D look without a 3D engine

Flutter has no production-ready 3D engine yet, and this game does not need
one. Each ring is cut into short pieces of tube. Every piece becomes a strip
of triangles with its own surface direction, each corner is lit in code (a
key light, a fill light, a highlight, and a reflected "sky" for metal), and
all the pieces from all rings are drawn far to near in one draw call. That
ordering makes rings pass over and under each other correctly. See
`lib/render/knot_painter.dart` and `lib/render/scene.dart`.

Building and recording one frame of a nine-ring knot takes about 1.9 ms on a
desktop CPU. It has not been profiled on a phone.

### Knots you can read and hit

A knot is only fun if you can tell the rings apart and hit the one you mean.
`lib/game/projection.dart` scores a camera angle by simulating taps that land
a little off target and counting how often they still pick the intended ring.
The generator throws away any knot whose hardest ring scores under 0.90 from
its best starting angle, and stores that angle with the level. Across the 446
shipped levels the lowest score is 0.90 and the median 0.96.

This is a calculation, not a playtest. It says a careful tap lands; it does
not say a level is fun.

### Rules in one place

`lib/game/knot.dart` holds the rules. `lib/game/solver.dart` is a second,
compact implementation used for search; a test plays random moves through
both and checks they agree.

## Before you release

These need your own accounts, so they are left for you:

1. **Bundle id and signing.** Replace `com.yourstudio.loopsmith` in
   `android/app/build.gradle.kts` and in Xcode, and set up release signing.
2. **AdMob ids.** The project uses Google's public test ids, which only show
   test ads. Replace the app ids in `android/app/src/main/AndroidManifest.xml`
   and `ios/Runner/Info.plist`, and the ad unit ids in
   `lib/services/ads.dart`. In the AdMob console, block gambling and other
   sensitive categories.
3. **Store products.** Create two non-consumable products named `remove_ads`
   and `starter_kit` in Google Play Console and App Store Connect. Prices
   shown in the app come from the stores.
4. **Privacy.** Publish a privacy policy, fill in the store data-safety
   forms, and add Apple's App Tracking Transparency prompt if you want
   personalised ads on iOS. Google's consent form for the EEA and UK is
   already wired in.
5. **Analytics.** Events go through `lib/services/analytics.dart` and are
   only printed in debug builds. Add a Firebase (or publisher) implementation
   of that one class.
6. **Purchase validation.** Purchases are trusted on the device. Add
   server-side receipt checks before selling anything valuable.

## Record a gameplay video

Build with `DEMO` set to a level number and the game opens on that level and
plays itself, one level after another:

```bash
flutter run --release --dart-define=DEMO=40
```

Record the phone's screen while it runs. That gives you clean footage for
store videos and ad creatives, with sound.

## What has and has not been checked

Checked in the environment this was built in:

- `flutter analyze` reports no issues.
- All 76 tests pass. They include playing every shipped level through the
  real play controller using its stored solution, checking that every hooked
  pair of rings really hooks and nothing else touches, checking every
  translation has the same keys and placeholders as English, and laying out
  every screen in every language on a 320 x 568 phone.
- The web build runs in Chromium: menus, play, pegs, tray, level clear, the
  weekly run, the language picker and the light theme were exercised and
  inspected.
- An Android debug build (APK) compiles, and the built app was inspected:
  the reminder receivers, notification permission, notification icon and all
  three level packs are in it.
- Sound files were measured: no clipping, and each music loop repeats without
  a jump at the seam.

Not checked, because it could not be done there:

- **Nothing was run on a real phone.** The Android build compiles but was
  never installed: touch feel, frame rate, vibration, ads, purchases and
  reminder notifications are unverified on a device.
- **No iOS build was made.** That needs a Mac. The reminder plugin may also
  need the notification-delegate lines from its README in `AppDelegate`.
- **Nobody has watched a person play.** Tap accuracy and difficulty are
  calculated, not observed. Watch five people play before you spend on ads.
- **Nobody has listened to the audio.** Eight effects are now real recordings
  (CC0, see `assets/audio/CREDITS.txt`); the other nine and all the music are
  synthesised by `tool/make_audio.py`. Replace any file with one of the same
  name and the game will use it. Licensed music is the biggest remaining gap.
- **The translations were not reviewed by native speakers.**
- **No ad test was run.** `docs/gameplay.mp4` is a starting clip only.

## Not included

- An online leaderboard for the daily knot, and cloud save across devices.
  Both need accounts and a backend. On Android, the system's own backup
  restores progress on a new phone when the user has backup turned on.
- Server-driven events. The weekly run is built into the app, so it works
  offline but cannot be changed without an update.
- Remote configuration. Every tunable number sits in
  `lib/game/economy.dart`, ready to move.

## Regenerating content

Levels (takes about a minute and a half; same output every time):

```bash
dart run tool/make_levels.dart
```

Audio:

```bash
pip install numpy scipy lameenc
```

```bash
python3 tool/make_audio.py
```

Icons:

```bash
pip install pillow
```

```bash
python3 tool/make_icons.py
```

The difficulty curve lives in `campaignSpec` in `lib/game/generator.dart`.

## Tests

```bash
flutter test
```
