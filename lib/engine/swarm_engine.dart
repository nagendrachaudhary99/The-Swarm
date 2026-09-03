import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

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
      final rows = await api!.sweep(radius: 200);
      final seen = <String>{};
      for (final r in rows) {
        seen.add(r.id);
        if (whispers.any((w) => w.remoteId == r.id)) continue;
        final metres = _metresFor(r.band);
        final angle = _rng.nextDouble() * pi * 2;
        final w = Whisper(
          id: _nextId++,
          body: r.body,
          pos: _clampWorld(you + Offset(cos(angle), sin(angle)) * metres),
          drift: Offset(_rng.nextDouble() - .5, _rng.nextDouble() - .5) * 0.7,
          life: r.remaining.inSeconds.toDouble().clamp(4, 90),
        )
          ..revealed = true
          ..remoteId = r.id;
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
      _say('tracking dropped');
    } else {
      target = w;
      w.nextThink = t + 1.2;
      _say('tracking · walk toward the ring');
      onToast?.call('◎ ring locked · they have been told');
    }
    notifyListeners();
  }

  void postWhisper(String body) {
    if (live) unawaited(api!.post(body, bloom: 'nightly'));
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
    if (d < 10) {
      bursts.add(Burst(
        w.pos,
        List.generate(14, (_) {
          final a = _rng.nextDouble() * pi * 2;
          final r = 6 + _rng.nextDouble() * 12;
          return Offset(cos(a), sin(a)) * r;
        }),
      ));
      target = null;
      shake = 1;
      flash = 1;
      _say('the ring popped · look up');
      onMirage?.call(w);
    }
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
