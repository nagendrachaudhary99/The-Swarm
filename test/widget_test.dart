import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

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
