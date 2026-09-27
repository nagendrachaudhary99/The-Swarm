# The Swarm

An anonymous campus sonar. The app is asleep most of the year; when it wakes,
you ping the dark for whispers that die in twenty seconds, and you can track one
until the ring pops.

**Interactive design reference:** https://claude.ai/code/artifact/aaa24d17-e7d6-46ff-9ed0-f4dc5ecac430
The Flutter build is a direct port of it — same mechanics, same numbers, same palette.

---

## Run it

```bash
flutter pub get
flutter run
```

No backend needed. With no session the app runs on the offline pool in Dart,
which is the point: if this is not fun offline, no backend will save it.
Connection is an upgrade, never a gate.

To show someone the thing itself with no door on it:

```bash
flutter run --dart-define=DEMO=true
```

There is no session in that mode and nothing pretends there is — every server
call still refuses. Never ship a build with it on.

### Keys

Nothing secret belongs in `lib/`. Both of these are build-time only, and
`.env.local` is ignored by git:

```bash
flutter run --dart-define=GOOGLE_MAPS_KEY=AIza...
GOOGLE_MAPS_KEY=AIza... bash scripts/stamp-maps-key.sh build/web
```

Leave the Maps key out entirely and the app draws its own dark map, which
costs nothing and still works offline.

### Applying the database

```bash
SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/db.sh -f supabase/006_hunts.sql
```

Migrations are numbered and go in order. The token is a personal access token
from https://supabase.com/dashboard/account/tokens — a full-account
credential, so it never gets committed and never appears in `lib/`.

---

## What is already built

| File | What it owns |
|---|---|
| `lib/engine/swarm_engine.dart` | Every rule. Energy, glow, decay, sweeps, hunt AI, the 10 m pop. One `update(dt)`. No Flutter widgets. |
| `lib/painters/sonar_painter.dart` | The whole map in one `CustomPainter` — ground, buildings, sweep, dashed hunt ring, rogue wedge, burst, your glow halo. |
| `lib/models/campus.dart` | Campus geometry in **metres**, plus `MapTransform`. Swap for real OSM geometry later; nothing else changes. |
| `lib/widgets/` | HUD, dock, whisper bubbles, the five sheets, the dormant screen. All dumb. |
| `lib/theme.dart` | The only place colours and text styles exist. Syne / Newsreader / JetBrains Mono. |
| `supabase/schema.sql` | PostGIS bands, RLS, the reaper cron, rate limits. |
| `supabase/006_hunts.sql` | The hunt loop, the freeze right and spores, in Postgres. Both ends of a hunt are people; neither learns who the other is. |
| `lib/data/swarm_api.dart` | Every call the app is allowed to make. Note what is absent: no `getWhisperLocation`, no way to read a beacon. |
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

- **Week 1** — ✅ the offline engine. Fun with fake data, or nothing else matters.
- **Week 2** — ✅ Supabase: campus-domain login, `whispers`, PostGIS bands,
  rooms, the safety layer, reaper cron.
- **Week 3** — ✅ real hunts: live beacons, freeze notifications, spore drops.
  See `supabase/006_hunts.sql`.
- **Week 4** — one dorm, one 24-hour emergence, 200 people. Posters that show
  only a countdown. Do not launch a campus; launch a building and let it leak.

### Signing in

Google, or a campus email and a password. There is no magic link and no
emailed code: a free Supabase project cannot reliably put either in an inbox,
so the sturdiest door is the one that never needs mail. Recovery mail is the
only mail left, and it is not a login.

The campus-domain rule is applied twice — once at the field, and once to the
session itself — because Google will vouch for any address alive.

### How a hunt actually works

The ring follows a live beacon, not the spot a whisper was dropped at, so you
are chasing someone who is walking. They are told the moment you start, and
they are told again each time the band changes.

**Standing still dissolves your signal.** Not an ability, not a class, not a
purchase — twelve seconds of not walking and the hunt dies, and while you are
frozen you drop out of everyone's sweep as well. There is deliberately nothing
anywhere in the schema that counters this.

Inside ten metres the ring bursts, `hunt_ping` returns `mirage`, and the row is
deleted. There is no second reading. Look up.
