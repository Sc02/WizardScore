# WizardScore

A scorekeeper for the card game **Wizard** (Ken Fisher, 1984). Runs entirely
offline on your phone — no account, no network, no ads. Track bids, tricks, the
running table, and the final winner.

- Android app, built with Flutter
- Play 3–6 players
- Optional house rules
- Full game history on your device

## Rules

The full ruleset is readable in the app — tap the 📖 icon in the Play tab's app bar.
Scoring tables and house rules also live in: wizard_rules/rules.pdf

## Install

Download `app-release.apk` from the project's GitHub **Releases** page and open it
on your phone. Android will ask you to allow installs from unknown sources — that's
expected for a sideloaded app.

```bash
# With the phone connected over USB and USB debugging enabled:
flutter install
```

> **Note:** The APK is signed with a debug key, so it is for personal use only
> and cannot be published to the Play Store. Android may warn that the app
> "is not from the Play Store"; tap through it.

## Use

1. Open **WizardScore**.
2. Go to the **Players** tab and add everyone at the table.
3. On the **Play** tab, tap **Start a new game** and seat the players in turn
   order — seat 1 is the first to be dealt.
4. Tap **Open score sheet**, then **Start round N**.
5. Enter everyone's bids, then **Lock bids**. The tricks column unlocks only
   after the lock, and **Round done** requires the tricks to add up to the cards
   dealt.
6. Repeat until the last round, then see the winner.

### Tips

- **Skip round** — the ⏭ icon in a round's app bar, or on the score sheet, skips
  a round without scoring it. It stays on the sheet as a gap.
- **Undo** — the ⏱ icon rewinds to any earlier round, discarding everything after
  it. Wins already credited are withdrawn.
- **Finish early** — **Finish game** on the score sheet ends a half-played game.
  Choose **Finish without saving** to close it without crediting anyone on the
  leaderboard.
- **House rule** — if enabled at game start, bids may not add up to exactly the
  number of tricks available (from round two on; round one is exempt since its
  only legal bids are 0 and 1). **Lock bids** greys out until the total differs.

## Data

Everything is stored locally in SQLite on the device. There is no account and no
cloud sync, so **uninstalling the app deletes all games and history
permanently**.

The History tab lists the 50 most recent games; older games are kept but not
displayed.

## Development

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
flutter pub get
flutter run          # debug on a connected device or emulator
flutter test         # run the test suite
flutter analyze      # static analysis
flutter build apk --release
```

The build output lands in `build/app/outputs/flutter-apk/`.

### Layout

| Path | What it holds |
| --- | --- |
| `lib/domain/rules.dart` | Pure Wizard rules and scoring, no Flutter imports |
| `lib/data/` | SQLite schema and repositories |
| `lib/models/` | Game, round, and player records |
| `lib/ui/screens/` | Play, score sheet, round entry, winner |
| `test/` | Unit tests and UI smoke tests |

## License

Released into the public domain under [CC0 1.0 Universal](LICENSE) — free to
use, copy, modify, and redistribute for any purpose, with no warranty of any
kind. The author claims no copyright and accepts no liability for any damage or
issues on any person's system caused by this app — use it at your own risk.
