import 'dart:ui';

import 'package:flutter/material.dart';

import '../engine/swarm_engine.dart';
import '../models/swarm_class.dart';
import '../theme.dart';

class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.engine,
    required this.countdown,
    required this.onClass,
    required this.onEmergence,
    required this.onDeep,
    required this.onInfo,
    required this.onStreak,
    required this.onPulse,
    required this.onMissed,
    required this.onRituals,
    required this.onDawn,
  });

  final SwarmEngine engine;
  final String countdown;
  final VoidCallback onClass;
  final VoidCallback onEmergence;
  final VoidCallback onDeep;
  final VoidCallback onInfo;
  final VoidCallback onStreak;
  final VoidCallback onPulse;
  final VoidCallback onMissed;
  final VoidCallback onRituals;
  final VoidCallback onDawn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              _Chip(
                onTap: onClass,
                accent: engine.cls.color,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(engine.cls.icon, size: 13, color: engine.cls.color),
                  const SizedBox(width: 6),
                  Text(engine.cls.label,
                      style: Swarm.data(size: 9.5, color: engine.cls.color, weight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 7),
              _Chip(
                onTap: onEmergence,
                accent: engine.bloom.accent,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(engine.bloom.name,
                      style: Swarm.data(
                          size: 9.5, color: engine.bloom.accent, weight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text(countdown, style: Swarm.data(size: 9.5, color: Swarm.fog)),
                ]),
              ),
              const Spacer(),
              _IconBtn(icon: Icons.waves_rounded, onTap: onDeep, tip: 'Deep Ocean'),
              const SizedBox(width: 7),
              _IconBtn(icon: Icons.wb_twilight_rounded, onTap: onDawn, tip: 'End the night'),
              const SizedBox(width: 7),
              _IconBtn(icon: Icons.info_outline_rounded, onTap: onInfo, tip: 'How it works'),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            _Stat(
              icon: Icons.local_fire_department_outlined,
              value: '${engine.streak}',
              label: 'NIGHTS',
              tint: Swarm.bard,
              onTap: onStreak,
            ),
            const SizedBox(width: 6),
            _Stat(value: '${engine.pulse}', label: 'AWAKE', live: true, onTap: onPulse),
            const SizedBox(width: 6),
            _Stat(value: '${engine.missed}', label: 'MISSED', onTap: onMissed),
            const SizedBox(width: 6),
            _Stat(
              value: '${engine.ritualsDone}/3',
              label: 'RITUALS',
              tint: Swarm.plankton,
              done: engine.ritualsDone == 3,
              onTap: onRituals,
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _Meter(
                label: 'ENERGY',
                value: engine.energy,
                readout: engine.energy.round().toString(),
                gradient: const [Color(0xFF2E7F9E), Swarm.plankton],
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _Meter(
                label: engine.glowLabel,
                value: engine.glow,
                readout: engine.glow.round().toString(),
                gradient: const [Color(0xFF3D5B7A), Color(0xFFBFE9FF), Color(0xFFFFF6D6)],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.child, required this.onTap, this.accent});
  final Widget child;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _Glass(
        radius: 9,
        border: accent?.withValues(alpha: .45),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: child,
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, required this.tip});
  final IconData icon;
  final VoidCallback onTap;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tip,
      child: GestureDetector(
        onTap: onTap,
        child: _Glass(
          radius: 9,
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 15, color: Swarm.fog),
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.readout,
    required this.gradient,
  });

  final String label;
  final double value;
  final String readout;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 9,
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Swarm.data(size: 8.5, color: Swarm.murk, tracking: 1.6)),
              Text(readout,
                  style: Swarm.data(size: 8.5, color: Swarm.foam, tracking: .4)
                      .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(children: [
              Container(height: 3, color: Colors.white.withValues(alpha: .07)),
              LayoutBuilder(
                builder: (_, c) => Container(
                  height: 3,
                  width: c.maxWidth * (value / 100).clamp(0.0, 1.0),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    required this.padding,
    required this.radius,
    this.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Swarm.trench.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border ?? Swarm.line),
          ),
          child: child,
        ),
      ),
    );
  }
}


/// One small readout in the status strip. Every number in here is a lever on
/// behaviour, so every one of them is tappable and explains itself.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.onTap,
    this.icon,
    this.tint,
    this.live = false,
    this.done = false,
  });

  final String value, label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? tint;
  final bool live, done;

  @override
  Widget build(BuildContext context) {
    final accent = done ? Swarm.plankton : tint;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: _Glass(
          radius: 8,
          border: done ? Swarm.plankton.withValues(alpha: .45) : null,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: accent ?? Swarm.bard),
                const SizedBox(width: 3),
              ],
              if (live) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF5BE58A),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0xFF5BE58A), blurRadius: 7)],
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Swarm.data(
                        size: 9.5,
                        color: accent ?? Swarm.foam,
                        weight: FontWeight.w700,
                        tracking: .2)),
              ),
              const SizedBox(width: 3),
              Text(label,
                  style: Swarm.data(size: 7.5, color: Swarm.murk, tracking: .8)),
            ],
          ),
        ),
      ),
    );
  }
}
