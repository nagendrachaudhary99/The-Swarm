# The Swarm

An anonymous campus sonar. The app is asleep most of the year; when it wakes,
you ping the dark for whispers that die in twenty seconds, and you can track one
until the ring pops.

**Interactive design reference:** https://claude.ai/code/artifact/aaa24d17-e7d6-46ff-9ed0-f4dc5ecac430
The Flutter build is a direct port of it — same mechanics, same numbers, same palette.

---

## Run it

Flutter is not installed on this machine yet. One time:

```bash
brew install --cask flutter     # ~1 GB
flutter doctor                  # follow whatever it tells you
```

Then, from this folder:

```bash
flutter create --project-name swarm --platforms=ios,android,macos .
flutter pub get
flutter run
```

`--project-name swarm` is required because this folder has spaces in its name.
It will not touch `lib/`, `pubspec.yaml` or anything already
written — it only generates the `ios/`, `android/` and `macos/` shells.

No backend needed for week 1. It runs entirely on fake data in Dart, which is
the point: if this is not fun offline, no backend will save it.

---

## What is already built

| File | What it owns |
|---|---|
| `lib/engine/swarm_engine.dart` | Every rule. Energy, glow, decay, sweeps, hunt AI, the 10 m pop. One `update(dt)`. No Flutter widgets. |
| `lib/painters/sonar_painter.dart` | The whole map in one `CustomPainter` — ground, buildings, sweep, dashed hunt ring, rogue wedge, burst, your glow halo. |
| `lib/models/campus.dart` | Campus geometry in **metres**, plus `MapTransform`. Swap for real OSM geometry later; nothing else changes. |
| `lib/widgets/` | HUD, dock, whisper bubbles, the five sheets, the dormant screen. All dumb. |
| `lib/theme.dart` | The only place colours and text styles exist. Syne / Newsreader / JetBrains Mono. |
| `supabase/schema.sql` | Week 2. PostGIS bands, RLS, the reaper cron, rate limits. |
| `.cursorrules` | Loaded automatically by Cursor. Keeps the architecture and the six safety rules intact when you vibe-code. |

## Playing it

- **Tap the dark** to walk (simulated at ×10 so a demo is playable).
- **PING** (8 energy) fires a sweep. Whatever it touches becomes readable for ~22s.
- **◍ boost** a whisper to brighten yourself. **◎ track** one to start a hunt.
- Walk at the ring. They will be told, and will **freeze** (signal dissolves) or **run**.
- Inside 10 m the ring **bursts** and gives you nothing but four blurred silhouettes.
- Glow 80 unlocks the **Deep Ocean**.

## The six rules that cannot be traded away

1. The 10 metre floor — `Band.mirage` returns nothing, forever.
2. Bands, not points — the client learns how far, never where.
3. The freeze right — being tracked is always announced, and always escapable.
4. Mutual consent — no reveal, chat or photo unless both sides tap yes.
5. 24-hour amnesia — deleted, not archived.
6. Scarcity — no feed, no infinite scroll, no practice mode.

They are in `.cursorrules` so the AI cannot quietly refactor them out.

## Roadmap

- **Week 1** — this. Make it fun with fake data.
- **Week 2** — Supabase: `.edu` magic link, `whispers` table, PostGIS bands, reaper cron.
- **Week 3** — real hunts: live beacons, freeze notifications, spore drops.
- **Week 4** — one dorm, one 24-hour emergence, 200 people. Posters that show
  only a countdown. Do not launch a campus; launch a building and let it leak.
