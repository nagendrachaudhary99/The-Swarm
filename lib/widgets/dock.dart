import 'dart:ui';

import 'package:flutter/material.dart';

import '../engine/swarm_engine.dart';
import '../models/swarm_class.dart';
import '../theme.dart';

class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.engine,
    required this.onPing,
    required this.onAbility,
    required this.onWhisper,
    required this.onSpore,
  });

  final SwarmEngine engine;
  final VoidCallback onPing;
  final VoidCallback onAbility;
  final VoidCallback onWhisper;
  final VoidCallback onSpore;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF504060B), Color(0xF504060B), Color(0x0004060B)],
          stops: [0, .45, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 14,
              child: Text(
                engine.hint,
                textAlign: TextAlign.center,
                style: Swarm.data(
                  size: 9,
                  color: engine.hintIsAlert ? Swarm.critical : Swarm.murk,
                  tracking: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(children: [
              _Act(
                flex: 155,
                icon: Icons.wifi_tethering_rounded,
                label: 'PING ·8',
                accent: Swarm.plankton,
                primary: true,
                enabled: engine.energy >= SwarmEngine.pingCost,
                onTap: onPing,
              ),
              const SizedBox(width: 8),
              _Act(
                icon: engine.cls.icon,
                label: engine.cls.ability,
                accent: engine.cls.color,
                enabled: engine.energy >= engine.cls.cost,
                onTap: onAbility,
              ),
              const SizedBox(width: 8),
              _Act(
                icon: Icons.mode_comment_outlined,
                label: 'WHISPER',
                enabled: true,
                onTap: onWhisper,
              ),
              const SizedBox(width: 8),
              _Act(
                icon: Icons.download_rounded,
                label: 'SPORE ·15',
                enabled: engine.energy >= SwarmEngine.sporeCost,
                onTap: onSpore,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Act extends StatefulWidget {
  const _Act({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.accent,
    this.primary = false,
    this.flex = 100,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final Color? accent;
  final bool primary;
  final int flex;

  @override
  State<_Act> createState() => _ActState();
}

class _ActState extends State<_Act> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Expanded(
      flex: widget.flex,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.enabled
              ? () {
                  setState(() => _down = false);
                  widget.onTap();
                }
              : null,
          child: AnimatedScale(
            scale: _down ? .95 : 1,
            duration: const Duration(milliseconds: 110),
            child: Opacity(
              opacity: widget.enabled ? 1 : .32,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: widget.primary ? null : Swarm.silt.withValues(alpha: .9),
                      gradient: widget.primary
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Swarm.plankton.withValues(alpha: .18),
                                Swarm.plankton.withValues(alpha: .04),
                              ],
                            )
                          : null,
                      border: Border.all(
                        color: accent?.withValues(alpha: widget.primary ? .42 : .42) ?? Swarm.line,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 17, color: accent ?? Swarm.fog),
                        const SizedBox(height: 4),
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Swarm.data(size: 8, color: accent ?? Swarm.fog, tracking: 1.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
