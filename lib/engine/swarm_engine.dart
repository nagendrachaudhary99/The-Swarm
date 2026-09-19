import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/swarm_api.dart';
import '../data/whisper_pool.dart';
import '../models/bloom.dart';
import '../models/campus.dart';
import '../models/swarm_class.dart';
import '../models/whisper.dart';
import '../theme.dart';

/// Proximity bands. This is the ONLY spatial information the real app is ever
/// allowed to hand a client. Server-side this is a PostGIS `ST_Distance`
/// wrapped in a `security definer` function — see supabase/schema.sql.
enum Band { mirage, critical, hot, warm, cold }

extension BandX on Band {
  String get label => switch (this) {
        Band.mirage => 'MIRAGE',
        Band.critical => 'CRITICAL',
        Band.hot => 'HOT',
        Band.warm => 'WARM',
        Band.cold => 'COLD',
      };

  Color get color => switch (this) {
        Band.mirage || Band.critical => Swarm.critical,
        Band.hot => Swarm.hot,
        Band.warm => Swarm.warm,
        Band.cold => Swarm.cold,
      };

  static Band of(double metres) {
    if (metres < 10) return Band.mirage;
    if (metres < 30) return Band.critical;
    if (metres < 80) return Band.hot;
    if (metres < 180) return Band.warm;
    return Band.cold;
  }
}

class SwarmEngine extends ChangeNotifier {
  SwarmEngine({SwarmClass? startClass})
      : cls = startClass ??
            SwarmClass.values[Random().nextInt(SwarmClass.values.length)] {
    _seed();
  }

  static const double pingCost = 8;
  static const double sporeCost = 15;
  static const double whisperCost = 0;

  /// Walking is simulated at ten times life so a demo is playable. Real builds
  /// take this straight from `geolocator` and the number disappears.
  static const double walkSpeed = 16;

  final _rng = Random();

  SwarmClass cls;
  double energy = 100;
  double glow = 34;
  Offset you = const Offset(104, 196);
  Offset? destination;

  final List<Whisper> whispers = [];
  final List<Sweep> sweeps = [];
  final List<Spore> spores = [];
  final List<Burst> bursts = [];

  Whisper? target;
  Offset? _sporeAnchor;

  /// Presentation state the painter reads. Kept here because it is driven by
  /// game events (the pop), not by widget lifecycle.
  double shake = 0;
  double flash = 0;
  final List<(Offset, double)> wake = [];
  double _wakeClock = 0;

  double t = 0;
  double _megaUntil = 0;
  double _stillUntil = 0;
  double _wedgeUntil = 0;
  double _lastPing = -9;
  int _nextId = 0;

  bool deepUnlocked = false;

  /// Which night this is. Nightly almost always; a bloom a handful of times a
  /// year, when the palette, the particles and the rules all change together.
  Bloom bloom = kBlooms.first;

  // The behavioural layer. Every one of these is visible in the HUD, because a
  // number nobody can see changes nobody's behaviour.
  int streak = 6;
  int shield = 1;
  int missed = 23;      // the campus was live for hours before you opened it
  int pulse = 412;
  double _pulseClock = 0;

  int caught = 0;
  int given = 0;
  int received = 0;
  double peakGlow = 34;
  double closest = 999;
  String? bestCatch;    // peak-end: the line you chose is the line you keep
  int ritualsDone = 0;
  final Set<String> _claimed = {};

  /// When an API is attached the engine stops inventing whispers and starts
  /// asking the server. Everything else — decay, glow, the hunt, the pop —
  /// is identical, because none of it ever depended on knowing a position.
  SwarmApi? api;

  // --- the hunt, once there is a person on the other end of it ------------
  // Offline these stay at their defaults and `_huntStep` keeps rolling dice,
  // which is the right behaviour for one phone. Online the dice are gone: the
  // band is measured between two real beacons, and whether the target freezes
  // is a decision somebody made.

  /// The last thing the server said about the ring. Drives the dashed circle
  /// exactly as the local hunt does — the painter cannot tell the difference,
  /// because the honest part of a hunt was never the direction.
  HuntTick hunt = HuntTick.none;

  /// The other half: what is happening to YOU. Rule three is this field being
  /// non-empty and the HUD saying so.
  HuntedState prey = HuntedState.calm;

  double _huntClock = 0;
  double _preyClock = 0;

  /// How long you have been standing still, and what the server currently
  /// believes about that. The freeze right is not an ability and costs
  /// nothing: it is what standing still means.
  double _stillFor = 0;
  bool _serverFrozen = false;

  /// True once the server has refused to narrow any further. Latched, because
  /// the whole point of the floor is that asking again does not help.
  bool mirageLatched = false;

  /// The slice of the world actually on screen, in metres, inset for the HUD
  /// and the dock. Set by the screen, which is the only thing that knows.
  ///
  /// This exists because a whisper's ANGLE is arbitrary — the server sends a
  /// band and never a bearing, so the direction on screen is invented. There
  /// is therefore no reason at all to invent one that puts the bubble outside
  /// the window, and every reason not to: on a desktop the visible strip is
  /// about 137 metres tall while a sweep reaches 140, so a vertical angle put
  /// the whisper off-screen with no way to reach it. The transform is fixed by
  /// MapTransform.cover, so zooming the map cannot bring it back.
  Rect? viewport;

  /// What the ground is currently showing. Set by the screen when the map
  /// camera moves; drives how far a sweep reaches and how loud a whisper has
  /// to be to survive that distance.
  double zoom = 18;
  bool get live => api != null;
  String? liveError;
  String hint = 'tap the dark to walk · sim ×10';
  bool hintIsAlert = false;

  final DateTime emergenceEnd =
      DateTime.now().add(const Duration(hours: 9, minutes: 41, seconds: 22));

  /// The screen wires these up. Keeping presentation out of the engine means
  /// week 2 can swap the whole thing for a Supabase stream without touching UI.
  void Function(String message)? onToast;
  void Function(Whisper popped)? onMirage;

  bool get megaphoneOn => t < _megaUntil;
  bool get stillWaterOn => t < _stillUntil;
  bool get wedgeOn => t < _wedgeUntil;

  String get glowTier => glow >= 80
      ? 'DEEP OCEAN'
      : glow >= 55
          ? 'MIDWATER'
          : glow >= 30
              ? 'TIDEPOOL'
              : 'SPARK';

  /// What the current zoom is showing. One place, so the HUD cannot describe
  /// a lens the sweep is not actually using.
  ({double radius, int minBoosts}) get lensNow => SwarmApi.lens(zoom);

  /// The rungs of the ladder, as zoom levels.
  static const lensRungs = [18.0, 16.5, 15.0, 13.5, 12.0];

  /// Step the lens by hand.
  ///
  /// On a build with a Maps key the camera is pinched and this is never used.
  /// Without one, `Ground` draws nothing at all — so there is no camera, no
  /// `onCameraMove`, and `zoom` is frozen at its opening value forever. The
  /// entire zoom ladder is unreachable on exactly the builds most people run:
  /// local development, and any deploy where the key was not set.
  void stepLens() {
    var i = lensRungs.indexOf(zoom);
    if (i < 0) i = 0;
    zoom = lensRungs[(i + 1) % lensRungs.length];
    notifyListeners();
  }

  double distanceTo(Whisper w) => (w.pos - you).distance;
  Band bandTo(Whisper w) => BandX.of(distanceTo(w));

  // ---------------------------------------------------------------- lifecycle

  void _seed() {
    final shuffled = List<String>.from(whisperPool)..shuffle(_rng);
    for (var i = 0; i < 20; i++) {
      _spawn(shuffled[i % shuffled.length]);
    }
    // Open with the water already alive — an empty first frame shows nothing.
    sweeps.add(Sweep(you, t: 1.9));
    final near = List<Whisper>.from(whispers)
      ..sort((a, b) => distanceTo(a).compareTo(distanceTo(b)));
    for (final w in near.take(3)) {
      w.revealed = true;
      w.age = _rng.nextDouble() * 4;
    }
  }

  Whisper _spawn(String body, {Offset? at, bool mine = false}) {
    final w = Whisper(
      id: _nextId++,
      body: body,
      pos: at ??
          Offset(
            18 + _rng.nextDouble() * (Campus.world.width - 36),
            24 + _rng.nextDouble() * (Campus.world.height - 54),
          ),
      drift: Offset(_rng.nextDouble() - .5, _rng.nextDouble() - .5) * 0.7,
      life: mine ? 26 : 19 + _rng.nextDouble() * 7,
      mine: mine,
    );
    whispers.add(w);
    return w;
  }

  // ------------------------------------------------------------------ actions

  void ping() {
    if (energy < pingCost || t - _lastPing < 1) return;
    energy -= pingCost;
    _lastPing = t;
    sweeps.add(Sweep(you));
    _say(live ? 'sweeping the real dark…' : 'sweeping… catch them before they fade');
    if (live) unawaited(_remoteSweep());
    notifyListeners();
  }

  /// The server answers with bodies and BANDS. It never sends a coordinate, so
  /// there is no true bearing to draw — we place each whisper at a real
  /// distance and an arbitrary angle. The ring you hunt with is honest; the
  /// direction is not knowable, which is the entire point.
  Future<void> _remoteSweep() async {
    try {
      // The map's zoom decides what a sweep is even allowed to return. One
      // curve, in SwarmApi.lens, so the ground and the sonar cannot disagree
      // about what should be visible at this scale.
      final l = SwarmApi.lens(zoom);
      final rows = await api!.sweep(radius: l.radius, minBoosts: l.minBoosts);
      final seen = <String>{};
      for (final r in rows) {
        seen.add(r.id);
        // Already on screen: refresh how loud it is rather than skipping it.
        // Virality is the one property that changes while you watch, and it
        // decides whether this whisper survives the next pull-back.
        final existing =
            whispers.where((w) => w.remoteId == r.id).firstOrNull;
        if (existing != null) {
          existing.boosts = r.boosts;
          continue;
        }
        final metres = _metresFor(r.band);
        final w = Whisper(
          id: _nextId++,
          body: r.body,
          pos: _placeAt(metres),
          drift: Offset(_rng.nextDouble() - .5, _rng.nextDouble() - .5) * 0.7,
          life: r.remaining.inSeconds.toDouble().clamp(4, 90),
        )
          ..revealed = true
          ..remoteId = r.id
          ..boosts = r.boosts;
        whispers.add(w);
        caughtThisSweep++;
      }
      liveError = null;
    } catch (e) {
      liveError = e.toString();
      _say('the water went quiet · check the connection', alert: true);
    }
    notifyListeners();
  }

  /// Put a whisper at a true distance and an angle you can actually see.
  ///
  /// The distance is the honest part and is never touched. The angle is
  /// invented — there is no bearing in any payload and there never will be —
  /// so it is chosen from whichever directions land inside the window. A
  /// bubble the sweep found and the screen cannot show is indistinguishable,
  /// to the person holding the phone, from a sweep that found nothing.
  Offset _placeAt(double metres) {
    final view = viewport;
    final start = _rng.nextDouble() * pi * 2;

    if (view != null && !view.isEmpty) {
      // Sixteen tries around the circle from a random start, so the direction
      // is still unpredictable rather than always, say, east.
      for (var i = 0; i < 16; i++) {
        final a = start + i * pi / 8;
        final p = you + Offset(cos(a), sin(a)) * metres;
        if (view.contains(p)) return _clampWorld(p);
      }

      // Nothing at that radius fits — the whisper is further away than the
      // window is tall. Put it at the edge in a visible direction rather than
      // hiding it: the band on the bubble still tells the truth about how far.
      final c = view.center;
      final toCentre = atan2(c.dy - you.dy, c.dx - you.dx);
      final p = you + Offset(cos(toCentre), sin(toCentre)) * metres;
      return Offset(
        p.dx.clamp(view.left, view.right),
        p.dy.clamp(view.top, view.bottom),
      );
    }

    return _clampWorld(you + Offset(cos(start), sin(start)) * metres);
  }

  /// Turn a band back into a plausible distance. The server refuses to be more
  /// precise than this, so neither can we.
  double _metresFor(String band) => switch (band) {
        'mirage' => 6 + _rng.nextDouble() * 3,
        'critical' => 10 + _rng.nextDouble() * 20,
        'hot' => 30 + _rng.nextDouble() * 50,
        'warm' => 80 + _rng.nextDouble() * 100,
        _ => 180 + _rng.nextDouble() * 40,
      };

  int caughtThisSweep = 0;

  void boost(Whisper w) {
    if (w.boosted) return;
    w.boosted = true;
    // Optimistic: the next sweep reconciles this against the server's count,
    // which is the authority. Waiting for that round trip to move a number the
    // person just pressed is how an app feels broken.
    w.boosts++;
    if (live && w.remoteId != null) unawaited(api!.boost(w.remoteId!));
    w.life += 4;
    given++;
    bestCatch = w.body;
    addGlow(2.6);
    onToast?.call('◍ you brightened someone');
    notifyListeners();
  }

  void track(Whisper w) {
    if (identical(target, w)) {
      target = null;
      hunt = HuntTick.none;
      mirageLatched = false;
      if (live) unawaited(api!.huntDrop());
      _say('tracking dropped');
    } else {
      target = w;
      w.nextThink = t + 1.2;
      hunt = HuntTick.none;
      mirageLatched = false;
      _huntClock = 0;
      _say('tracking · walk toward the ring');
      // Offline this toast is a promise the app cannot keep. Online it is
      // literally true: hunt_start writes the alert row before it returns.
      onToast?.call('◎ ring locked · they have been told');
      if (live && w.remoteId != null) unawaited(_startRemoteHunt(w));
    }
    notifyListeners();
  }

  /// Ask the server to open the hunt. It answers with the opening band, or
  /// with 'mirage' when you were already inside the floor — in which case no
  /// hunt exists to ping and the ring pops on the spot.
  Future<void> _startRemoteHunt(Whisper w) async {
    try {
      final band = await api!.huntStart(w.remoteId!);
      if (band == 'mirage') {
        _burst(w);
        return;
      }
      if (band == 'lost') {
        if (identical(target, w)) target = null;
        _say('signal lost · they are already gone');
        notifyListeners();
        return;
      }
      hunt = HuntTick(band: band, state: 'open', seconds: 0);
      notifyListeners();
    } catch (e) {
      liveError = e.toString();
      // A refused hunt must not strand the ring on screen pretending to work.
      if (identical(target, w)) target = null;
      _say('the hunt would not open · check the connection', alert: true);
      notifyListeners();
    }
  }

  void postWhisper(String body) {
    // `bloom.id`, not 'nightly'. Hardcoding it meant the bloom you picked
    // changed how long the whisper lived on YOUR screen — lifeMultiplier is
    // applied locally a few lines down — while the server went on killing it
    // at twenty-two seconds. So the two copies disagreed: you could still read
    // your own whisper long after everyone else's sweep had dropped it, which
    // is the most confusing possible version of this bug, because the person
    // who posted it is the one person who cannot notice.
    if (live) unawaited(api!.post(body, bloom: bloom.id));
    final w = _spawn(body, at: you, mine: true);
    w.revealed = true;
    if (megaphoneOn) w.life *= 2;
    w.incoming = [
      2 + _rng.nextDouble() * 4,
      7 + _rng.nextDouble() * 6,
      14 + _rng.nextDouble() * 6,
    ];
    onToast?.call('your whisper is in the water');
    notifyListeners();
  }

  void dropSpore() {
    if (energy < sporeCost) return;
    energy -= sporeCost;
    spores.add(Spore(you, _rng.nextDouble()));
    _sporeAnchor = you;
    // The server keeps its own copy at your beacon and will not show it to
    // anyone until you have walked away from it — same twenty-five metres
    // `_bloomSpores` uses here, so the two halves agree about what "away" is.
    if (live) {
      unawaited(api!.sporeDrop().catchError((e) {
        // Three at a time is enforced in Postgres, so this is the one refusal
        // worth repeating out loud.
        onToast?.call('● you have enough spores out');
        return '';
      }));
    }
    onToast?.call('● spore dropped · walk away to let it bloom');
    notifyListeners();
  }

  void useAbility() {
    if (energy < cls.cost) return;
    switch (cls) {
      case SwarmClass.bard:
        energy -= cls.cost;
        _megaUntil = t + 90;
        for (final w in whispers) {
          if (w.revealed) w.life += w.remaining * .6;
        }
        onToast?.call('♪ megaphone · the night burns longer');
      case SwarmClass.rogue:
        if (target == null) {
          onToast?.call('track a whisper first');
          return;
        }
        energy -= cls.cost;
        _wedgeUntil = t + 60;
        onToast?.call('◎ wedge open · 60 seconds of direction');
      case SwarmClass.mage:
        energy -= cls.cost;
        _stillUntil = t + 20;
        onToast?.call('❄ still water · nothing fades, you are cloaked');
    }
    notifyListeners();
  }

  void setClass(SwarmClass c) {
    cls = c;
    notifyListeners();
  }

  void setBloom(Bloom b) {
    bloom = b;
    if (b.everyoneGlows) glow = 100;   // Diwali: status switches off for a night
    onToast?.call('${b.name} · ${b.rule}');
    notifyListeners();
  }

  /// Three small, finishable things. Completing all three protects the streak
  /// and then the app stops asking — the night has an end, which is the whole
  /// difference between a ritual and a compulsion.
  List<Ritual> get rituals => [
        Ritual('catch', 'Catch five whispers', caught, 5, 6),
        Ritual('boost', 'Brighten three people', given, 3, 6),
        Ritual('close', 'Get within 30 m of someone', closest < 30 ? 1 : 0, 1, 9),
      ];

  void _checkRituals() {
    var done = 0;
    for (final r in rituals) {
      if (!r.done) continue;
      done++;
      if (_claimed.add(r.id)) {
        addGlow(r.reward.toDouble());
        onToast?.call('✓ ${r.label.toUpperCase()}');
      }
    }
    if (done != ritualsDone) {
      ritualsDone = done;
      if (done == 3) {
        streak++;
        onToast?.call('☀ NIGHT COMPLETE · STREAK $streak');
      }
    }
  }

  String get glowLabel =>
      glow >= 80 ? 'DEEP OCEAN' : '${(80 - glow).ceil()} TO DEEP OCEAN';

  void walkTo(Offset worldPoint) {
    destination = Offset(
      worldPoint.dx.clamp(6.0, Campus.world.width - 6),
      worldPoint.dy.clamp(6.0, Campus.world.height - 6),
    );
  }

  void addGlow(double v) {
    final before = glow;
    glow = (glow + v).clamp(0.0, 100.0);
    peakGlow = peakGlow > glow ? peakGlow : glow;
    if (before < 80 && glow >= 80 && !deepUnlocked) {
      deepUnlocked = true;
      onToast?.call('◎ DEEP OCEAN UNLOCKED');
    }
  }

  void _say(String message, {bool alert = false}) {
    hint = message;
    hintIsAlert = alert;
  }

  // -------------------------------------------------------------------- frame

  void update(double dt) {
    t += dt;

    _walk(dt);
    energy = (energy + 1.1 * dt).clamp(0.0, 100.0);
    glow = (glow - 0.16 * dt).clamp(0.0, 100.0);

    _advanceSweeps(dt);
    _advanceWhispers(dt);
    _topUp(dt);
    _bloomSpores();
    _liveHunt(dt);
    _lensWatch(dt);

    bursts.removeWhere((b) {
      b.t += dt;
      return b.done;
    });

    _pulseClock += dt;
    if (_pulseClock > 1.6) {
      _pulseClock = 0;
      pulse = (pulse + _rng.nextInt(9) - 4).clamp(330, 486);
    }
    _checkRituals();

    shake = max(0, shake - dt * 2.2);
    flash = max(0, flash - dt * 3.4);

    _wakeClock += dt;
    if (destination != null && _wakeClock > .07) {
      _wakeClock = 0;
      wake.add((you, t));
      if (wake.length > 46) wake.removeAt(0);
    }

    notifyListeners();
  }

  // ------------------------------------------------------------ the lens

  /// Which rung of `SwarmApi.lens` is currently on screen, and how long since
  /// the pinch stopped moving.
  ({double radius, int minBoosts}) _lens = SwarmApi.lens(18);
  double _lensSettle = 0;

  /// True while the map is being redrawn at a new scale. The HUD says so,
  /// because otherwise pulling back looks like whispers vanishing for no
  /// reason.
  bool reframing = false;

  /// Zooming is a question, and until now nothing answered it.
  ///
  /// The map's zoom has always decided what a sweep is *allowed* to return —
  /// that is what `lens` is for — but the only thing that ever re-asked the
  /// server was `ping()`. So you pulled the map back, the lens widened, and
  /// the screen kept showing the same close-in whispers until you spent eight
  /// energy on another ping. The single gesture the whole map idea rests on
  /// did nothing at all.
  ///
  /// This is not a ping and costs no energy. A ping is a thing you fire into
  /// the dark. This is the dark being redrawn at the scale you asked for.
  void _lensWatch(double dt) {
    if (!live) return;

    final now = SwarmApi.lens(zoom);
    if (now.radius != _lens.radius || now.minBoosts != _lens.minBoosts) {
      _lens = now;
      // A pinch crosses several rungs on the way past. Each one is not a
      // separate question, so the clock restarts rather than accumulating.
      _lensSettle = .45;
      return;
    }

    if (_lensSettle > 0) {
      _lensSettle -= dt;
      if (_lensSettle <= 0) unawaited(_reframe());
    }
  }

  /// Re-ask the campus what is visible at this scale.
  Future<void> _reframe() async {
    final floor = SwarmApi.lens(zoom).minBoosts;

    // Pulling back raises the floor, so whatever no longer clears it stops
    // being drawn. This is the half that makes zooming out mean something:
    // fewer, louder, further away. Your own whisper always survives — you are
    // allowed to see the thing you just said.
    final gone = whispers
        .where((w) => w.remoteId != null && !w.mine && w.boosts < floor)
        .toList();

    for (final w in gone) {
      if (identical(target, w)) {
        target = null;
        hunt = HuntTick.none;
        mirageLatched = false;
        unawaited(api!.huntDrop());
        _say('tracking dropped · too quiet to see from this far out');
      }
      whispers.remove(w);
    }

    reframing = true;
    notifyListeners();

    await _remoteSweep();

    reframing = false;
    _say(floor == 0
        ? 'everything within earshot'
        : 'only whispers with $floor+ boosts carry this far');
    notifyListeners();
  }

  // ------------------------------------------------------------- live hunts

  /// Join the real campus.
  ///
  /// Attaching the API is not enough on its own: rule three says being hunted
  /// is *announced*, and a three-second poll is not an announcement — it is a
  /// delay with a promise attached. So this also opens the socket that makes
  /// the telling immediate. The poll stays as the floor under it, because a
  /// dropped socket must not quietly switch the rule off.
  void goLive(SwarmApi attach) {
    api = attach;
    final open = _alerts;
    if (open != null) unawaited(attach.drop(open));
    _alerts = null;

    // Clear any freeze left behind by a previous session, unconditionally.
    //
    // `frozen` lives on the server and outlives the tab that set it, but
    // `_serverFrozen` starts false on every fresh load — so _thaw() would see
    // "I did not freeze this" and leave a stale flag in place forever. A
    // person who froze once then closed the app came back permanently
    // invisible, with nothing on screen saying so.
    //
    // Opening the app is not an escape from anything: there is no hunt yet.
    _serverFrozen = false;
    _stillFor = 0;
    unawaited(attach.freezeSignal(false).catchError((_) => false));

    try {
      _alerts = attach.liveHunted((band) {
        // Push, not poll. The row that triggered this has no hunter column in
        // it, which is the only reason a socket on that table is safe to open.
        final was = prey;
        prey = HuntedState(
          hunters: was.hunters == 0 ? 1 : was.hunters,
          nearest: band,
          frozen: was.frozen,
        );
        if (!was.hunted) {
          onToast?.call('◎ someone is tracking you · stand still to dissolve');
          _say('you are being hunted · stop walking to disappear', alert: true);
        }
        notifyListeners();
        // Reconcile against the authoritative count promptly; the socket knows
        // a hunt started, not how many are running.
        _preyClock = 3;
      });
    } catch (e) {
      // A refused socket is survivable — _tickPrey still runs. It is not
      // survivable silently, because the guarantee is weaker without it.
      liveError = e.toString();
    }
    notifyListeners();
  }

  RealtimeChannel? _alerts;

  @override
  void dispose() {
    final c = _alerts;
    final a = api;
    if (c != null && a != null) unawaited(a.drop(c));
    _alerts = null;
    super.dispose();
  }

  /// The two clocks that only tick when there is a server, plus the one rule
  /// that costs nothing and cannot be countered.
  ///
  /// Both polls are cheap and deliberately slow. A hunt is a walk across a
  /// campus, not a shooter, and a ring that updates once a second is already
  /// faster than anyone can move.
  void _liveHunt(double dt) {
    if (!live) return;

    _stillness(dt);

    if (target != null && !mirageLatched) {
      _huntClock += dt;
      if (_huntClock > 1.1) {
        _huntClock = 0;
        unawaited(_tickHunt());
      }
    }

    _preyClock += dt;
    if (_preyClock > 3) {
      _preyClock = 0;
      unawaited(_tickPrey());
    }
  }

  /// The freeze right. Not an ability, not a purchase, not a class: standing
  /// still is the whole mechanism, and it is available to everyone who is
  /// being hunted for as long as they are willing to stop walking.
  void _stillness(double dt) {
    // Freezing is an ESCAPE, not a resting state, and conflating the two made
    // everybody invisible to everybody.
    //
    // sweep() drops whispers whose author is frozen — correctly, because a
    // dissolved signal has to be dissolved to everyone. But standing still is
    // what a person does almost all of the time: a phone on a table is still,
    // and reading a whisper is still. So freezing on stillness alone meant two
    // people in the same room both went dark within two seconds of opening the
    // app and neither could see anything the other said.
    //
    // Rule three is "anyone TRACKED is notified and can dissolve their signal
    // by standing still". Nobody tracking you means nothing to escape from.
    if (!prey.hunted) {
      _stillFor = 0;
      _thaw();
      return;
    }

    if (destination != null) {
      _stillFor = 0;
      _thaw();
      return;
    }

    _stillFor += dt;
    // A second and a half, so that putting the phone down between taps is not
    // mistaken for a decision.
    if (_stillFor > 1.5 && !_serverFrozen) {
      _serverFrozen = true;
      unawaited(api!.freezeSignal(true).catchError((_) => false));
      onToast?.call('❄ holding still · your signal is dissolving');
    }
  }

  void _thaw() {
    if (!_serverFrozen) return;
    _serverFrozen = false;
    unawaited(api!.freezeSignal(false).catchError((_) => false));
  }

  Future<void> _tickHunt() async {
    try {
      final tick = await api!.huntPing();
      final was = hunt.state;
      hunt = tick;

      if (tick.state != was) {
        switch (tick.state) {
          case 'frozen':
            _say('signal dissolving · they have stopped moving');
          case 'dissolved':
            target = null;
            _say('they held still · the signal is gone');
            onToast?.call('◌ you lost them · that was their right');
          case 'gone':
            target = null;
            _say('signal lost · they left the water');
          case 'none':
            target = null;
          case 'open':
            if (was == 'frozen') {
              _say('they are moving again · cut them off', alert: true);
            }
        }
      }
      liveError = null;
      notifyListeners();
    } catch (e) {
      liveError = e.toString();
    }
  }

  Future<void> _tickPrey() async {
    try {
      final now = await api!.hunted();
      final was = prey;
      prey = now;

      // Told, every time it starts being true. This is rule three and it is
      // not conditional on anything.
      if (now.hunted && !was.hunted) {
        onToast?.call('◎ someone is tracking you · stand still to dissolve');
        _say('you are being hunted · stop walking to disappear', alert: true);
      }
      notifyListeners();
    } catch (_) {
      // The prey poll failing must never be louder than the hunt itself.
    }
  }

  void _walk(double dt) {
    final dest = destination;
    if (dest == null) return;
    final delta = dest - you;
    final d = delta.distance;
    if (d < 1.5) {
      destination = null;
      return;
    }
    you += delta / d * min(walkSpeed * dt, d);
  }

  void _advanceSweeps(double dt) {
    sweeps.removeWhere((s) {
      s.t += dt;
      for (final w in whispers) {
        if (!w.revealed && (w.pos - s.origin).distance <= s.radius) {
          w.revealed = true;
          w.age = 0;
          caught++;
          w.life *= bloom.lifeMultiplier;
          if (megaphoneOn) w.life *= 1.6;
        }
      }
      return s.done;
    });
  }

  void _advanceWhispers(double dt) {
    final frozen = stillWaterOn;

    for (var i = whispers.length - 1; i >= 0; i--) {
      final w = whispers[i];
      w.aliveFor += dt;
      // curiosity gap: whispers die out there whether you look or not
      if (!w.revealed && w.aliveFor > 55) {
        missed++;
        whispers.removeAt(i);
        continue;
      }
      if (w.revealed && !frozen) w.age += dt;
      if (w.revealed) closest = min(closest, distanceTo(w).toDouble());

      if (w.mine && w.incoming.isNotEmpty && w.age > w.incoming.first) {
        w.incoming = w.incoming.sublist(1);
        addGlow(4.4);
        received++;
        onToast?.call('◍ someone ${40 + _rng.nextInt(220)}m away boosted you');
      }

      if (identical(w, target)) {
        _huntStep(w, dt);
      } else if (w.revealed) {
        w.pos += w.drift * dt * 0.7;
      }

      if (w.revealed && w.dead) {
        if (identical(w, target)) {
          target = null;
          _say('signal lost · they let it fade');
        }
        whispers.removeAt(i);
      }
    }
  }

  /// The prey half of the loop. Being hunted is not passive: you are told, and
  /// standing still dissolves your signal. Being found is always a choice.
  void _huntStep(Whisper w, double dt) {
    // Online the dice are gone. `_liveHunt` has already asked the server what
    // the band is and what the other person is doing, and this only has to
    // draw it.
    if (live && w.remoteId != null) {
      _remoteHuntStep(w, dt);
      return;
    }

    final d = distanceTo(w);

    if (t > w.nextThink) {
      w.nextThink = t + 1.8;
      if (d < 130) {
        w.state = _rng.nextDouble() < bloom.freezeChance
            ? TargetState.frozen
            : TargetState.fleeing;
        _say(
          w.state == TargetState.frozen
              ? 'signal dissolving · they have stopped moving'
              : 'they are moving away · cut them off',
          alert: w.state == TargetState.fleeing,
        );
      } else {
        w.state = TargetState.drift;
      }
    }

    switch (w.state) {
      case TargetState.fleeing:
        final a = atan2(w.pos.dy - you.dy, w.pos.dx - you.dx);
        w.pos = _clampWorld(w.pos + Offset(cos(a), sin(a)) * 10 * dt);
      case TargetState.drift:
        w.pos = _clampWorld(w.pos + w.drift * dt * 2);
      case TargetState.frozen:
        break;
    }

    // The 10 metre floor. The ring bursts and returns nothing, forever.
    if (d < 10) _burst(w);
  }

  /// Online, the ring is measured instead of invented.
  ///
  /// The band is the only truth the server will tell, so the bubble is held at
  /// that distance and keeps whatever angle it already had. The direction is
  /// still a lie, exactly as it is after a sweep — there has never been a
  /// bearing in any payload and this does not add one.
  void _remoteHuntStep(Whisper w, double dt) {
    if (mirageLatched) return;

    final delta = w.pos - you;
    final a = delta.distance < 0.001
        ? _rng.nextDouble() * pi * 2
        : atan2(delta.dy, delta.dx);
    final want = _metresFor(hunt.band);

    // Ease rather than teleport. A band is a step change and a ring that jumps
    // is a ring nobody walks toward.
    w.pos = _clampWorld(
      Offset.lerp(w.pos, you + Offset(cos(a), sin(a)) * want,
              min(1, dt * 2.2)) ??
          w.pos,
    );

    // The server knows whether they are standing still. It does not know, and
    // must not guess, whether moving means running away.
    w.state =
        hunt.frozen ? TargetState.frozen : TargetState.drift;

    if (hunt.burst) _burst(w);
  }

  /// The floor, reached. Everything here is a refusal dressed as an effect:
  /// the ring is deleted, nothing replaces it, and the app has no further
  /// answer about who that was.
  void _burst(Whisper w) {
    mirageLatched = true;
    bursts.add(Burst(
      w.pos,
      List.generate(14, (_) {
        final a = _rng.nextDouble() * pi * 2;
        final r = 6 + _rng.nextDouble() * 12;
        return Offset(cos(a), sin(a)) * r;
      }),
    ));
    target = null;
    hunt = HuntTick.none;
    shake = 1;
    flash = 1;
    _say('the ring popped · look up');
    onMirage?.call(w);
  }

  Offset _clampWorld(Offset p) => Offset(
        p.dx.clamp(10.0, Campus.world.width - 10),
        p.dy.clamp(10.0, Campus.world.height - 10),
      );

  void _topUp(double dt) {
    if (whispers.length < 16 && _rng.nextDouble() < dt * 1.3) {
      _spawn(whisperPool[_rng.nextInt(whisperPool.length)]);
    }
  }

  void _bloomSpores() {
    final anchor = _sporeAnchor;
    if (anchor == null) return;
    if ((you - anchor).distance > 25) {
      if (spores.isNotEmpty && !spores.last.bloomed) {
        spores.last.bloomed = true;
        onToast?.call('● your spore bloomed where you stood');
      }
      _sporeAnchor = null;
    }
  }
}


/// One of tonight's three finishable things.
class Ritual {
  const Ritual(this.id, this.label, this.value, this.goal, this.reward);
  final String id, label;
  final int value, goal, reward;
  bool get done => value >= goal;
  double get progress => (value / goal).clamp(0.0, 1.0);
}
