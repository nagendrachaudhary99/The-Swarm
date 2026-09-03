import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/swarm_api.dart';
import '../engine/swarm_engine.dart';
import '../main.dart' show whereAmI;
import '../models/campus.dart';
import '../painters/sonar_painter.dart';
import '../theme.dart';
import '../widgets/dock.dart';
import '../widgets/hud.dart';
import '../widgets/sheets.dart';
import '../widgets/whisper_bubble.dart';

class EmergenceScreen extends StatefulWidget {
  const EmergenceScreen({super.key});

  @override
  State<EmergenceScreen> createState() => _EmergenceScreenState();
}

class _EmergenceScreenState extends State<EmergenceScreen>
    with SingleTickerProviderStateMixin {
  late final SwarmEngine _engine;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  String? _toast;

  @override
  void initState() {
    super.initState();
    _engine = SwarmEngine()
      ..onToast = _showToast
      ..onMirage = (w) => showMirageSheet(context, _engine, w);

    _goLive();

    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _engine.update(dt.clamp(0.0, 0.05));
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _engine.dispose();
    super.dispose();
  }

  /// Join the real campus. If any step fails the app simply stays offline —
  /// the whole experience works either way.
  Future<void> _goLive() async {
    if (!SwarmApi.ready) return;
    try {
      final api = SwarmApi.instance;
      if (!api.signedIn) return;          // the gate owns sign-in, not us
      final at = await whereAmI();
      await api.beacon(at.lat, at.lon);
      if (!mounted) return;
      setState(() => _engine.api = api);
      _showToast('◉ live on campus');
    } catch (e) {
      if (mounted) _showToast('◌ offline · running on the local pool');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    setState(() => _toast = message);
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted && _toast == message) setState(() => _toast = null);
    });
  }

  /// Dawn is 06:00. The night is the unit, every night.
  String get _emergenceLeft {
    final now = DateTime.now();
    var dawn = DateTime(now.year, now.month, now.day, 6);
    if (!dawn.isAfter(now)) dawn = dawn.add(const Duration(days: 1));
    final s = dawn.difference(now);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(s.inHours)}:${p(s.inMinutes % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final view = Size(constraints.maxWidth, constraints.maxHeight);
          final tf = MapTransform.cover(view, Campus.world);

          return Stack(
            children: [
              // --- the dark. tap it to walk. ---
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _engine.walkTo(tf.toWorld(d.localPosition)),
                  child: CustomPaint(
                    painter: SonarPainter(
                      engine: _engine,
                      tf: tf,
                      reduceMotion: reduceMotion,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),

              // --- caught whispers ---
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _engine,
                  builder: (context, _) => Stack(
                    children: [
                      for (final w in _engine.whispers.where((w) => w.revealed))
                        () {
                          final at = tf.toScreen(w.pos);
                          final left = (at.dx - 98).clamp(6.0, view.width - 202);
                          final top = (at.dy - 14).clamp(96.0, view.height - 190);
                          // hand the painter the card's centre for its hairline
                          w.anchor = Offset(left + 98, top + 40);
                          return Positioned(
                            left: left,
                            top: top,
                            child: WhisperBubble(whisper: w, engine: _engine),
                          );
                        }(),
                    ],
                  ),
                ),
              ),

              // --- instruments ---
              Positioned(
                top: MediaQuery.of(context).padding.top,
                left: 0,
                right: 0,
                child: ListenableBuilder(
                  listenable: _engine,
                  builder: (context, _) => Hud(
                    engine: _engine,
                    countdown: _emergenceLeft,
                    onClass: () => showClassSheet(context, _engine),
                    onEmergence: () => showBloomSheet(context, _engine),
                    onDeep: () => showDeepSheet(context, _engine),
                    onInfo: () => showInfoSheet(context),
                    onStreak: () => showStatSheet(context, _engine, 'streak'),
                    onPulse: () => showStatSheet(context, _engine, 'pulse'),
                    onMissed: () => showStatSheet(context, _engine, 'missed'),
                    onRituals: () => showRitualSheet(context, _engine),
                    onDawn: () => showDawnReport(context, _engine),
                  ),
                ),
              ),

              // --- controls ---
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom,
                child: ListenableBuilder(
                  listenable: _engine,
                  builder: (context, _) => Dock(
                    engine: _engine,
                    onPing: _engine.ping,
                    onAbility: _engine.useAbility,
                    onWhisper: () => showWhisperSheet(context, _engine),
                    onSpore: _engine.dropSpore,
                  ),
                ),
              ),

              // --- toast ---
              if (_toast != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 108 + MediaQuery.of(context).padding.bottom,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                        color: Swarm.silt.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Swarm.plankton.withValues(alpha: .3)),
                      ),
                      child: Text(
                        _toast!.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Swarm.data(size: 9.5, color: Swarm.foam, tracking: 1.1),
                      ),
                    ),
                  ),
                ),

            ],
          );
        },
      ),
    );
  }
}
