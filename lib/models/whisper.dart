import 'dart:ui';

enum TargetState { drift, frozen, fleeing }

/// One anonymous line, dropped at a point on campus, dying on a timer.
/// [pos] is in world metres, never latitude/longitude — the real client
/// receives a distance band from the server and nothing else.
class Whisper {
  Whisper({
    required this.id,
    required this.body,
    required this.pos,
    required this.drift,
    required this.life,
    this.mine = false,
  });

  final int id;
  final String body;
  final bool mine;

  Offset pos;
  Offset drift;

  bool revealed = false;
  bool boosted = false;
  double age = 0;
  double aliveFor = 0;
  double life;

  TargetState state = TargetState.drift;
  double nextThink = 0;

  /// Simulated inbound boosts on your own whispers, in seconds after posting.
  List<double> incoming = const [];

  /// The server's id, when this whisper came from the real campus rather than
  /// the offline pool. Null means it is simulated.
  String? remoteId;

  /// Where its bubble ended up on screen, so the painter can draw a hairline
  /// back to the exact spot the whisper came from. Set by the screen.
  Offset? anchor;

  double get remaining => life - age;
  bool get dead => age >= life;

  /// Last four seconds fade out.
  double get opacity => remaining < 4 ? (remaining / 4).clamp(0.0, 1.0) : 1.0;
}

class Sweep {
  Sweep(this.origin, {this.t = 0, this.duration = 2.4, this.maxRadius = 132});
  final Offset origin;
  double t;
  final double duration;
  final double maxRadius;
  double get radius => (t / duration) * maxRadius;
  bool get done => t >= duration;
}

class Spore {
  Spore(this.pos, this.phase);
  final Offset pos;
  final double phase;
  bool bloomed = false;
}

class Burst {
  Burst(this.pos, this.particles, {this.t = 0, this.duration = 0.9});
  final Offset pos;
  final List<Offset> particles;
  double t;
  final double duration;
  double get progress => t / duration;
  bool get done => t >= duration;
}
