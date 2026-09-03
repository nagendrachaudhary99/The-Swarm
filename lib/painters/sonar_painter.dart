import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/swarm_engine.dart';
import '../models/bloom.dart';
import '../models/campus.dart';
import '../models/whisper.dart';
import '../theme.dart';

/// Drifting plankton. Nothing in the ocean is ever perfectly still, and an
/// empty black rectangle is the fastest way to make an app feel dead.
class _Mote {
  _Mote(Random r)
      : x = r.nextDouble() * Campus.world.width,
        y = r.nextDouble() * Campus.world.height,
        radius = .35 + r.nextDouble() * 1.35,
        alpha = .05 + r.nextDouble() * .25,
        speed = .5 + r.nextDouble() * 1.9,
        phase = r.nextDouble() * pi * 2,
        depth = .25 + r.nextDouble() * .75,
        sway = .4 + r.nextDouble() * 1.2;

  final double x, y, radius, alpha, speed, phase, depth, sway;
  bool get front => depth > .68;
}

/// A lit window. A campus at night is mostly people you cannot see.
class _Window {
  _Window(Random r)
      : dx = .1 + r.nextDouble() * .8,
        dy = .14 + r.nextDouble() * .72,
        phase = r.nextDouble() * pi * 2,
        on = r.nextDouble() < .58,
        warm = r.nextDouble() < .3;

  final double dx, dy, phase;
  final bool on, warm;
}

/// The entire map, sweep, hunt ring and glow — one painter, no game engine.
/// Repaints off the engine directly, so the widget tree above it stays still.
class SonarPainter extends CustomPainter {
  SonarPainter({
    required this.engine,
    required this.tf,
    required this.reduceMotion,
  }) : super(repaint: engine);

  final SwarmEngine engine;
  final MapTransform tf;
  final bool reduceMotion;

  static final _rng = Random(7);
  static final List<_Mote> _motes = List.generate(120, (_) => _Mote(_rng));
  static final Map<String, List<_Window>> _windows = {
    for (final b in Campus.buildings)
      if (!b.open)
        b.name: List.generate(
          max(4, (b.rect.width * b.rect.height / 240).floor()),
          (_) => _Window(_rng),
        ),
  };
  static ui.Image? _grain;

  /// One 96×96 tile of noise, generated once. Film grain is what stops a flat
  /// dark screen reading as an unfinished wireframe.
  static Future<void> warmUp() async {
    if (_grain != null) return;
    const n = 96;
    final px = Uint8List(n * n * 4);
    final r = Random(3);
    for (var i = 0; i < px.length; i += 4) {
      final v = 120 + r.nextInt(135);
      px[i] = px[i + 1] = px[i + 2] = v;
      px[i + 3] = 255;
    }
    final buf = await ui.ImmutableBuffer.fromUint8List(px);
    final desc = ui.ImageDescriptor.raw(buf,
        width: n, height: n, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    _grain = (await codec.getNextFrame()).image;
  }

  Bloom get b => engine.bloom;
  Color ac(double a) => b.accent.withValues(alpha: a);
  Color ac2(double a) => b.accent2.withValues(alpha: a);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (engine.shake > 0.001) {
      final s = engine.shake * 7;
      canvas.translate((_rng.nextDouble() * 2 - 1) * s, (_rng.nextDouble() * 2 - 1) * s);
    }

    _ground(canvas, size);
    _grid(canvas, size);
    _contours(canvas);
    _paths(canvas);
    _buildings(canvas);
    _motesLayer(canvas, front: false);
    _spores(canvas);
    _unrevealed(canvas);
    _radarArm(canvas, size);
    _sweeps(canvas);
    _leaders(canvas);
    _huntRing(canvas, size);
    _bursts(canvas);
    _wake(canvas);
    _you(canvas);
    _motesLayer(canvas, front: true);

    canvas.restore();
    _atmosphere(canvas, size);

    if (engine.flash > 0.001) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFF8CA5).withValues(alpha: engine.flash * .28),
      );
    }
  }

  // The dark is centred on you — walking actually changes what the map feels like.
  void _ground(Canvas canvas, Size size) {
    final c = tf.toScreen(engine.you);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          size.height * .9,
          b.ground,
          const [0.0, 0.34, 0.7, 1.0],
        ),
    );

    if (reduceMotion) return;
    // Slow caustics — light on water, three bands at different speeds.
    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.plus);
    for (var i = 0; i < 3; i++) {
      final y = ((engine.t * (7 + i * 4) + i * 260) % (size.height + 320)) - 160;
      canvas.drawRect(
        Rect.fromLTWH(0, y - 90, size.width, 180),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, y - 90),
            Offset(0, y + 90),
            [
              ac(0),
              ac(.020 - i * .004),
              ac(0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
    canvas.restore();
  }

  void _grid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x0A78AAC8)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= Campus.world.width; x += 30) {
      final sx = tf.toScreen(Offset(x, 0)).dx;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), p);
    }
    for (var y = 0.0; y <= Campus.world.height; y += 30) {
      final sy = tf.toScreen(Offset(0, y)).dy;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), p);
    }
  }

  /// Depth soundings at 50/100/150/200 m, so distance stays readable at a
  /// glance even when you are not hunting anything.
  void _contours(Canvas canvas) {
    final c = tf.toScreen(engine.you);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF82B9D7).withValues(alpha: .055);
    for (final m in const [50.0, 100.0, 150.0, 200.0]) {
      final r = m * tf.scale;
      canvas.drawCircle(c, r, ring);
      final tp = TextPainter(
        text: TextSpan(
          text: '${m.round()}m',
          style: Swarm.data(
              size: 6.5, tracking: .4, color: const Color(0xFF82B9D7).withValues(alpha: .13)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx + r + 4, c.dy - 9));
    }
  }

  void _paths(Canvas canvas) {
    final p = Paint()
      ..color = const Color(0x1D78AAC8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in Campus.paths) {
      canvas.drawLine(tf.toScreen(a), tf.toScreen(b), p);
    }
  }

  void _buildings(Canvas canvas) {
    for (final b in Campus.buildings) {
      final near = (1 - (b.rect.center - engine.you).distance / 190).clamp(0.0, 1.0);
      final r = Rect.fromPoints(tf.toScreen(b.rect.topLeft), tf.toScreen(b.rect.bottomRight));
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(7));

      if (b.open) {
        _dashedRRect(
          canvas,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF78AAC8).withValues(alpha: .09 + near * .14),
        );
      } else {
        canvas.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [
              const Color(0xFF1A293A).withValues(alpha: .52 + near * .28),
              const Color(0xFF0A111A).withValues(alpha: .62 + near * .22),
            ]),
        );
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF82B4D2).withValues(alpha: .11 + near * .24),
        );

        canvas.save();
        canvas.clipRRect(rr);
        for (final w in _windows[b.name] ?? const <_Window>[]) {
          if (!w.on) continue;
          if (!reduceMotion && sin(engine.t * .6 + w.phase) <= -.94) continue;
          final a = (.16 + near * .34) * (w.warm ? 1 : .8);
          canvas.drawRect(
            Rect.fromLTWH(r.left + w.dx * r.width, r.top + w.dy * r.height, 1.5, 1.2),
            Paint()
              ..color = (w.warm ? const Color(0xFFFFCE8C) : const Color(0xFFA8DCF0))
                  .withValues(alpha: a),
          );
        }
        canvas.restore();
      }

      final tp = TextPainter(
        text: TextSpan(
          text: b.name,
          style: Swarm.data(
            size: 7,
            tracking: .6,
            color: const Color(0xFFA0C3D7).withValues(alpha: .24 + near * .42),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// One system, six behaviours. This is what makes each bloom feel like a
  /// different planet rather than a re-skin.
  void _motesLayer(Canvas canvas, {required bool front}) {
    final kind = b.drift;
    for (final m in _motes) {
      if (m.front != front) continue;

      double y;
      if (kind == Drift.rain || kind == Drift.snow ||
          kind == Drift.lantern || kind == Drift.ember) {
        final dir = (kind == Drift.lantern || kind == Drift.ember) ? -1.0 : 1.0;
        final speed = switch (kind) {
          Drift.rain => 90.0,
          Drift.snow => 7.0,
          Drift.ember => 16.0,
          _ => 9.0,
        };
        final h = Campus.world.height + 40;
        y = (m.y + dir * (reduceMotion ? 0 : engine.t) * speed * (.6 + m.depth)) % h;
        if (y < 0) y += h;
        y -= 20;
      } else {
        final drift = reduceMotion ? 0.0 : (engine.t * m.speed) % (Campus.world.height + 40);
        y = (m.y - drift) % Campus.world.height;
        if (y < 0) y += Campus.world.height;
      }

      final x = kind == Drift.rain
          ? m.x
          : m.x + (reduceMotion ? 0 : sin(engine.t * .35 + m.phase) * m.sway * (kind == Drift.snow ? 5 : 2.4));
      final at = tf.toScreen(Offset(x, y));
      final lit = (1 - (Offset(x, y) - engine.you).distance / 150).clamp(0.0, 1.0);

      switch (kind) {
        case Drift.rain:
          canvas.drawLine(
            at,
            at + Offset(-2, m.radius * 9 * (.5 + m.depth)),
            Paint()
              ..strokeWidth = .9
              ..color = b.particle.withValues(alpha: m.alpha * .7),
          );
        case Drift.pigment:
          final hue = kPigments[m.phase.floor() % kPigments.length];
          canvas.drawCircle(
            at,
            m.radius * 7,
            Paint()
              ..shader = ui.Gradient.radial(at, m.radius * 7, [
                hue.withValues(alpha: m.alpha * .9),
                hue.withValues(alpha: 0),
              ]),
          );
        case Drift.lantern || Drift.ember:
          final r = m.radius * (kind == Drift.lantern ? 9 : 5);
          canvas.drawCircle(
            at,
            r,
            Paint()
              ..shader = ui.Gradient.radial(at, r, [
                b.particle.withValues(alpha: (m.alpha * 1.5).clamp(0.0, 1.0)),
                b.particle.withValues(alpha: 0),
              ]),
          );
        default:
          canvas.drawCircle(
            at,
            m.radius * (kind == Drift.snow ? 1.5 : (.7 + m.depth * .6)),
            Paint()..color = b.particle.withValues(alpha: m.alpha * (.35 + lit * .85)),
          );
      }
    }
  }

  /// Real sonar never stops turning. This is what makes the screen feel alive
  /// between pings without adding a single bit of information.
  void _radarArm(Canvas canvas, Size size) {
    if (reduceMotion) return;
    final c = tf.toScreen(engine.you);
    final ang = engine.t * .42;
    final reach = max(size.width, size.height) * 1.1;

    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: reach), ang - .62, .62, false)
        ..close(),
      Paint()
        ..shader = ui.Gradient.radial(c, reach, [
          ac(.055), ac(.022), ac(0),
        ], const [0.0, 0.55, 1.0]),
    );
    canvas.drawLine(
      c,
      c + Offset(cos(ang), sin(ang)) * reach,
      Paint()
        ..strokeWidth = 1
        ..color = ac(.10),
    );
  }

  void _spores(Canvas canvas) {
    for (final s in engine.spores) {
      final c = tf.toScreen(s.pos);
      final p = (engine.t * 1.4 + s.phase) % 1;
      canvas.drawCircle(
        c,
        4 + p * 13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFBFE9FF).withValues(alpha: (1 - p) * .4),
      );
      canvas.drawCircle(
          c, 3, Paint()..color = s.bloomed ? const Color(0xFFBFE9FF) : const Color(0xFF5E7E96));
      if (s.bloomed) {
        canvas.drawCircle(
          c,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8
            ..color = const Color(0xFFBFE9FF).withValues(alpha: .35),
        );
      }
    }
  }

  /// Whispers you have not pinged yet: a flicker at the edge of nothing.
  /// Barely visible on purpose — it is what makes PING worth pressing.
  void _unrevealed(Canvas canvas) {
    for (final w in engine.whispers) {
      if (w.revealed) continue;
      final f = reduceMotion ? .12 : .09 + .10 * sin(engine.t * 2.2 + w.id);
      final c = tf.toScreen(w.pos);
      canvas.drawCircle(c, 1.4, Paint()..color = ac(f));
      if (!reduceMotion && f > .16) {
        canvas.drawCircle(
            c, 4.5, Paint()..color = ac((f - .16) * .22));
      }
    }
  }

  void _sweeps(Canvas canvas) {
    for (final s in engine.sweeps) {
      final c = tf.toScreen(s.origin);
      final p = s.t / s.duration;
      final r = s.radius * tf.scale;
      final a = (1 - p) * .6;
      if (r > 26) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(c, r, [
              ac(0),
              ac(a * .16),
            ], const [0.0, 1.0], TileMode.clamp, null, c, r - 26),
        );
      }
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 - p * 1.4
          ..color = ac2(a),
      );
      if (r > 11) {
        canvas.drawCircle(
          c,
          r - 11,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = ac(a * .28),
        );
      }
    }
  }

  /// Hairlines from each bubble back to the exact spot the whisper came from.
  /// Without them a floating card is decoration; with them it is a reading.
  void _leaders(Canvas canvas) {
    for (final w in engine.whispers) {
      final anchor = w.anchor;
      if (!w.revealed || anchor == null) continue;
      final isTarget = identical(w, engine.target);
      final base = isTarget ? Swarm.rogue : b.accent;
      final a = (isTarget ? .5 : .26) * w.opacity;
      final at = tf.toScreen(w.pos);
      canvas.drawLine(
        anchor,
        at,
        Paint()
          ..strokeWidth = .8
          ..color = base.withValues(alpha: a),
      );
      canvas.drawCircle(
        at,
        2.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = base.withValues(alpha: (a + .25).clamp(0.0, 1.0)),
      );
    }
  }

  /// A ring around YOU with the radius of the distance — it says how far,
  /// never where. Under 10 m it is already gone; the engine popped it.
  void _huntRing(Canvas canvas, Size size) {
    final tgt = engine.target;
    if (tgt == null) return;

    final d = engine.distanceTo(tgt);
    final band = BandX.of(d);
    final c = tf.toScreen(engine.you);
    final r = d * tf.scale;
    final frozen = tgt.state == TargetState.frozen;

    final beat = frozen || reduceMotion
        ? 0.0
        : (sin(engine.t * (d < 30 ? 9 : d < 80 ? 5 : 2.6)) * .5 + .5);
    final alpha = frozen ? .11 : .30 + beat * .42;

    if (!frozen) {
      // soft bloom under the ring so the band colour reads at a glance
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..color = band.color.withValues(alpha: alpha * .10),
      );
    }

    _dashedCircle(
      canvas,
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = frozen ? 1 : 1.8
        ..color = band.color.withValues(alpha: alpha),
      dash: frozen ? 1 : 9,
      gap: 7,
      phase: reduceMotion ? 0 : -engine.t * .35,
    );

    if (engine.wedgeOn) {
      final ang = atan2(tgt.pos.dy - engine.you.dy, tgt.pos.dx - engine.you.dx);
      final reach = max(size.width, size.height);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..arcTo(Rect.fromCircle(center: c, radius: reach), ang - .22, .44, false)
          ..close(),
        Paint()
          ..shader = ui.Gradient.radial(c, reach, [
            Swarm.rogue.withValues(alpha: .22),
            Swarm.rogue.withValues(alpha: 0),
          ]),
      );
    }
  }

  void _bursts(Canvas canvas) {
    for (final b in engine.bursts) {
      final p = b.progress;
      for (final part in b.particles) {
        canvas.drawCircle(
          tf.toScreen(b.pos + part * p * 1.6),
          2.4 * (1 - p),
          Paint()..color = const Color(0xFFFF7891).withValues(alpha: (1 - p) * .95),
        );
      }
      for (var k = 0; k < 2; k++) {
        final pp = (p * 1.4 - k * .18).clamp(0.0, 1.0);
        canvas.drawCircle(
          tf.toScreen(b.pos),
          8 + pp * 54,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * (1 - pp)
            ..color = const Color(0xFFFF5A78).withValues(alpha: (1 - pp) * (k == 0 ? .55 : .22)),
        );
      }
    }
  }

  void _wake(Canvas canvas) {
    for (final (pos, at) in engine.wake) {
      final age = engine.t - at;
      if (age > 2.4) continue;
      canvas.drawCircle(
        tf.toScreen(pos),
        1.6 + age * 1.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..color = const Color(0xFF96E1FF).withValues(alpha: (1 - age / 2.4) * .15),
      );
    }
  }

  void _you(Canvas canvas) {
    final c = tf.toScreen(engine.you);
    final gl = engine.glow / 100;
    final halo = 18 + gl * 30 + (reduceMotion ? 0 : sin(engine.t * 1.7) * 3);

    // Three stacked glows: bloom, body, core. This is the entire status system.
    canvas.drawCircle(
      c,
      halo * 2.1,
      Paint()
        ..shader = ui.Gradient.radial(c, halo * 2.1, [
          const Color(0xFF78D2FF).withValues(alpha: .10 + gl * .16),
          const Color(0x0078D2FF),
        ]),
    );
    canvas.drawCircle(
      c,
      halo,
      Paint()
        ..shader = ui.Gradient.radial(c, halo, [
          const Color(0xFFAAEBFF).withValues(alpha: .34 + gl * .36),
          const Color(0x0096E1FF),
        ]),
    );

    if (engine.stillWaterOn) {
      _dashedCircle(
        canvas,
        c,
        halo * .78,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Swarm.mage.withValues(alpha: .6),
        dash: 3,
        gap: 4,
        phase: engine.t * .2,
      );
    }
    if (engine.megaphoneOn) {
      canvas.drawCircle(
        c,
        halo * .62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Swarm.bard.withValues(alpha: .4),
      );
    }

    canvas.drawCircle(c, 4.6, Paint()..color = const Color(0xFFF2FBFF));
    canvas.drawCircle(
      c,
      7.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFF2FBFF).withValues(alpha: .35),
    );

    final dest = engine.destination;
    if (dest != null) {
      final p = (engine.t * 2) % 1;
      final dc = tf.toScreen(dest);
      canvas.drawCircle(
        dc,
        4 + p * 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFBFE9FF).withValues(alpha: .5 * (1 - p)),
      );
      canvas.drawCircle(
          dc, 1.8, Paint()..color = const Color(0xFFBFE9FF).withValues(alpha: .6));
    }
  }

  void _atmosphere(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * .46),
          max(size.width, size.height) * .78,
          const [Color(0x00000000), Color(0x9E000000)],
          const [0.0, 1.0],
        ),
    );

    final grain = _grain;
    if (grain == null || reduceMotion) return;
    // A shader ignores Paint.color, so the 3.5% is applied to the whole layer.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.overlay
        ..color = Colors.white.withValues(alpha: .035),
    );
    canvas.clipRect(Offset.zero & size);
    canvas.translate((engine.t * 40) % 96 - 96, (engine.t * 27) % 96 - 96);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width + 96, size.height + 96),
      Paint()
        ..shader = ui.ImageShader(
          grain,
          TileMode.repeated,
          TileMode.repeated,
          Float64List.fromList(
              const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        ),
    );
    canvas.restore();
  }

  // ------------------------------------------------------------------ helpers

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint,
      {double dash = 8, double gap = 6, double phase = 0}) {
    if (r < 1) return;
    final step = (dash + gap) / r;
    final arc = dash / r;
    if (step <= 0.001) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var a = phase; a < phase + pi * 2; a += step) {
      canvas.drawArc(rect, a, arc, false, paint);
    }
  }

  void _dashedRRect(Canvas canvas, RRect rr, Paint paint) {
    final path = Path()..addRRect(rr);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, min(d + 4, metric.length)), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(SonarPainter old) =>
      old.tf.scale != tf.scale || old.reduceMotion != reduceMotion;
}
