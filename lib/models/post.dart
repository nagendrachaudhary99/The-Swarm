import 'dart:ui';

/// What a post is for. The kind changes how long it lives, how far it reaches
/// and whether anyone can respond to it — a joke and a cry for help should not
/// behave the same way.
enum Kind { thought, news, afraid, help }

extension KindX on Kind {
  String get label => switch (this) {
        Kind.thought => 'THOUGHT',
        Kind.news => 'NEWS',
        Kind.afraid => 'SCARED',
        Kind.help => 'HELP NOW',
      };

  String get hint => switch (this) {
        Kind.thought => 'Anything on your mind',
        Kind.news => 'Something happening on campus',
        Kind.afraid => 'Something worrying you',
        Kind.help => 'Something wrong, right now, here',
      };

  Color get colour => switch (this) {
        Kind.thought => const Color(0xFF6FF3CE),
        Kind.news => const Color(0xFF7FA8FF),
        Kind.afraid => const Color(0xFFFFC46B),
        Kind.help => const Color(0xFFFF3B5C),
      };

  /// Seconds. Ordinary talk is fleeting; a call for help must not vanish while
  /// people are still walking towards it.
  double get life => switch (this) {
        Kind.thought => 60,
        Kind.news => 240,
        Kind.afraid => 300,
        Kind.help => 1800,
      };

  /// Metres. Help reaches further than gossip.
  double get reach => switch (this) {
        Kind.thought => 200,
        Kind.news => 350,
        Kind.afraid => 350,
        Kind.help => 600,
      };

  /// Only these two ask anything of the people who see them.
  bool get callsForPeople => this == Kind.help || this == Kind.afraid;

  /// A phone should only buzz for the one that matters.
  bool get pushes => this == Kind.help;
}

/// One anonymous post standing somewhere on campus.
///
/// There is no author field, no handle, no colour that persists between posts.
/// Two posts by the same person are, to everyone else, two strangers.
class Post {
  Post({
    required this.id,
    required this.body,
    required this.kind,
    required this.metres,
    required this.bearingUnknown,
    required this.life,
  });

  final int id;
  final String body;
  final Kind kind;

  /// How far away they are. This is the *only* spatial fact anyone ever gets,
  /// and it is deliberately rounded — see [distanceLabel].
  double metres;

  /// Always true. Kept as a named field so the intent survives future edits:
  /// direction is never sent, so nobody can walk a bearing to a person.
  final bool bearingUnknown;

  double life;
  double age = 0;

  int coming = 0;       // people who said they are on their way
  bool iAmComing = false;
  bool revealed = false;
  String? revealedAs;   // only ever set by the poster, about themselves

  double get remaining => life - age;
  bool get dead => age >= life;

  /// Rounded to the nearest 10 m and never below 10. Precision here would let
  /// somebody stand still, watch the number, and narrow a person down.
  String get distanceLabel {
    final m = metres < 10 ? 10 : (metres / 10).round() * 10;
    return '${m}m away';
  }

  String get proximityWord {
    if (metres < 60) return 'right near you';
    if (metres < 160) return 'close by';
    if (metres < 350) return 'on campus';
    return 'far side of campus';
  }
}
