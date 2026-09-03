import 'package:flutter/material.dart';

import '../engine/swarm_engine.dart';
import '../models/whisper.dart';
import '../theme.dart';

/// One caught whisper. Twenty-two seconds of somebody's honesty, with a
/// life bar draining under it so you can watch it go.
class WhisperBubble extends StatelessWidget {
  const WhisperBubble({
    super.key,
    required this.whisper,
    required this.engine,
  });

  final Whisper whisper;
  final SwarmEngine engine;

  @override
  Widget build(BuildContext context) {
    final isTarget = identical(engine.target, whisper);
    final band = engine.bandTo(whisper);
    final metres = (engine.distanceTo(whisper) / 5).round() * 5;

    return Opacity(
      opacity: whisper.opacity,
      child: SizedBox(
        width: 196,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF0142C2C), Color(0xF0090E16)],
            ),
            border: Border.all(
              color: whisper.mine
                  ? const Color(0xFFBFE9FF).withValues(alpha: .34)
                  : Swarm.plankton.withValues(alpha: isTarget ? .5 : .2),
            ),
            borderRadius: whisper.mine
                ? const BorderRadius.only(
                    topLeft: Radius.circular(13),
                    topRight: Radius.circular(13),
                    bottomLeft: Radius.circular(13),
                    bottomRight: Radius.circular(4),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(13),
                    topRight: Radius.circular(13),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(13),
                  ),
            boxShadow: [
              BoxShadow(
                color: Swarm.plankton.withValues(alpha: .18),
                blurRadius: 22,
                spreadRadius: -8,
              ),
              const BoxShadow(color: Color(0xE6000000), blurRadius: 30, spreadRadius: -12),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(whisper.body, style: Swarm.voice(size: 12.4)),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _Mini(
                      label: whisper.boosted ? '◍ boosted' : '◍ boost',
                      active: whisper.boosted,
                      onTap: () => engine.boost(whisper),
                    ),
                    if (!whisper.mine) ...[
                      const SizedBox(width: 6),
                      _Mini(
                        label: isTarget ? '◎ tracking' : '◎ track',
                        active: isTarget,
                        activeColor: Swarm.rogue,
                        onTap: () => engine.track(whisper),
                      ),
                    ],
                    const Spacer(),
                    Text('${band.label} · ≈${metres}m',
                        style: Swarm.data(size: 8.5, color: Swarm.murk, tracking: .8)),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: (whisper.remaining / whisper.life).clamp(0.0, 1.0),
                    minHeight: 2,
                    backgroundColor: Colors.white.withValues(alpha: .08),
                    valueColor: AlwaysStoppedAnimation(
                      (isTarget ? Swarm.rogue : Swarm.plankton).withValues(alpha: .55),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = Swarm.plankton,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? activeColor.withValues(alpha: .45) : Swarm.line,
          ),
          color: active ? activeColor.withValues(alpha: .08) : null,
        ),
        child: Text(
          label.toUpperCase(),
          style: Swarm.data(size: 8.5, color: active ? activeColor : Swarm.fog),
        ),
      ),
    );
  }
}
