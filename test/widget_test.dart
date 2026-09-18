import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:swarm/data/swarm_api.dart';
import 'package:swarm/engine/swarm_engine.dart';
import 'package:swarm/models/swarm_class.dart';
import 'package:swarm/models/whisper.dart';
import 'package:swarm/painters/sonar_painter.dart';
import 'package:swarm/models/campus.dart';

void main() {
  group('proximity bands', () {
    test('under 10 metres is a mirage and nothing else', () {
      expect(BandX.of(0), Band.mirage);
      expect(BandX.of(9.99), Band.mirage);
      expect(BandX.of(10), isNot(Band.mirage));
    });

    test('bands widen outward and never invert', () {
      expect(BandX.of(20), Band.critical);
      expect(BandX.of(60), Band.hot);
      expect(BandX.of(120), Band.warm);
      expect(BandX.of(400), Band.cold);
    });
  });

  group('engine', () {
    test('a ping costs energy and reveals what it sweeps over', () {
      final e = SwarmEngine();
      final before = e.energy;
      e.ping();
      expect(e.energy, before - SwarmEngine.pingCost);

      final hidden = e.whispers.where((w) => !w.revealed).length;
      for (var i = 0; i < 200; i++) {
        e.update(1 / 60);
      }
      expect(e.whispers.where((w) => !w.revealed).length, lessThan(hidden));
    });

    test('whispers decay and are removed, never archived', () {
      final e = SwarmEngine();
      e.postWhisper('this should not survive the night');
      final mine = e.whispers.firstWhere((w) => w.mine);
      for (var i = 0; i < 60 * 60; i++) {
        e.update(1 / 60);
      }
      expect(e.whispers.contains(mine), isFalse);
    });

    test('closing to 10 metres pops the ring and clears the target', () {
      final e = SwarmEngine();
      final w = e.whispers.first
        ..revealed = true
        ..pos = e.you + const Offset(12, 0)
        ..state = TargetState.frozen;

      Whisper? popped;
      e.onMirage = (p) => popped = p;
      e.track(w);
      expect(e.target, same(w));

      w.pos = e.you + const Offset(5, 0);
      e.update(1 / 60);

      expect(popped, same(w));
      expect(e.target, isNull, reason: 'the ring must not survive the pop');
      expect(e.shake, greaterThan(0));
    });

    test('glow is clamped and unlocks the deep ocean exactly once', () {
      final e = SwarmEngine();
      var toasts = 0;
      e.onToast = (m) => m.contains('DEEP OCEAN') ? toasts++ : null;
      e.addGlow(500);
      expect(e.glow, 100);
      expect(e.deepUnlocked, isTrue);
      e.addGlow(10);
      expect(toasts, 1);
    });

    test('rogue track needs a target and refunds nothing when it has none', () {
      final e = SwarmEngine(startClass: SwarmClass.rogue);
      final before = e.energy;
      e.useAbility();
      expect(e.energy, before, reason: 'a no-op ability must not charge');
      expect(e.wedgeOn, isFalse);
    });
  });

  // The hunt is the one loop with a second person in it, so these are tests of
  // the promises made to that person rather than of the mechanics.
  group('the hunt', () {
    test('a burst latches, so asking again never narrows further', () {
      final e = SwarmEngine();
      final w = e.whispers.first
        ..revealed = true
        ..pos = e.you + const Offset(12, 0)
        ..state = TargetState.frozen;

      e.track(w);
      expect(e.mirageLatched, isFalse);

      // walk the last two metres
      w.pos = e.you + const Offset(8, 0);
      e.update(1 / 60);

      expect(e.mirageLatched, isTrue);
      expect(e.target, isNull);
      expect(e.hunt.band, 'lost', reason: 'the floor returns nothing at all');
    });

    test('dropping a hunt clears the latch so a new one can start', () {
      final e = SwarmEngine();
      final a = e.whispers.first..revealed = true;
      e.track(a);
      e.track(a); // tracking the same one again drops it
      expect(e.target, isNull);
      expect(e.mirageLatched, isFalse);
    });

    test('standing still costs nothing — the freeze right is never priced', () {
      final e = SwarmEngine();
      final before = e.energy;
      e.destination = null;
      for (var i = 0; i < 60 * 5; i++) {
        e.update(1 / 60);
      }
      expect(e.energy, greaterThanOrEqualTo(before),
          reason: 'energy regenerates while still; it must never be spent');
      expect(e.prey.frozen, isFalse, reason: 'offline there is nobody to tell');
    });

    test('a tick the server never answered is not a hunt', () {
      expect(HuntTick.none.over, isTrue);
      expect(HuntTick.none.burst, isFalse);
      expect(HuntedState.calm.hunted, isFalse);
    });

    test('every way a hunt ends reads as over, and only one as a burst', () {
      HuntTick t(String s) => HuntTick(band: 'hot', state: s, seconds: 0);
      expect(t('burst').over, isTrue);
      expect(t('burst').burst, isTrue);
      expect(t('dissolved').over, isTrue);
      expect(t('gone').over, isTrue);
      expect(t('none').over, isTrue);

      expect(t('open').over, isFalse);
      // A frozen hunt is still running: they can start moving again.
      expect(t('frozen').over, isFalse);
      expect(t('frozen').frozen, isTrue);
    });

    test('the wire format carries a band and never a position', () {
      final tick = HuntTick.fromRow(
          {'band': 'critical', 'state': 'open', 'seconds': 42});
      expect(tick.band, 'critical');
      expect(tick.seconds, 42);

      final hunted = HuntedState.fromRow(
          {'hunters': 2, 'nearest': 'hot', 'frozen': true});
      expect(hunted.hunted, isTrue);
      expect(hunted.hunters, 2);
      expect(hunted.nearest, 'hot');

      // There is no field for who, in either direction, because there is no
      // column for it in the tables these come from.
      expect(tick.toString(), isNot(contains('user')));
    });

    test('a missing row degrades to calm rather than to an exception', () {
      expect(HuntTick.fromRow(const {}).state, 'none');
      expect(HuntTick.fromRow(const {}).band, 'lost');
      expect(HuntedState.fromRow(const {}).hunted, isFalse);
    });
  });

  test('the painter renders a full frame without throwing', () async {
    await SonarPainter.warmUp();

    final e = SwarmEngine();
    e.ping();
    e.postWhisper('a whisper to draw');
    e.dropSpore();
    final w = e.whispers.firstWhere((x) => x.revealed)
      ..anchor = const Offset(120, 200);
    e.track(w);
    e.useAbility();

    const size = Size(390, 780);
    final tf = MapTransform.cover(size, Campus.world);

    // Several frames: sweep expanding, ring pulsing, motes drifting, grain on.
    for (var i = 0; i < 90; i++) {
      e.update(1 / 60);
      final recorder = PictureRecorder();
      SonarPainter(engine: e, tf: tf, reduceMotion: false)
          .paint(Canvas(recorder), size);
      recorder.endRecording().dispose();
    }

    // and again with motion reduced, which takes different branches
    final recorder = PictureRecorder();
    SonarPainter(engine: e, tf: tf, reduceMotion: true)
        .paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
  });
}
