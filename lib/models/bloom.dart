import 'package:flutter/material.dart';

/// How a bloom's particles behave. One system, six worlds — this is what makes
/// each bloom feel like a different planet rather than a re-skin.
enum Drift { plankton, ember, pigment, lantern, rain, snow }

/// The Swarm is awake every night. A bloom is one of the rare nights — finals,
/// Holi, Diwali, first monsoon, first snow — when the palette, the particles
/// and the rules all change. Daily habit, rare peaks.
class Bloom {
  const Bloom({
    required this.id,
    required this.name,
    required this.when,
    required this.daysAway,
    required this.accent,
    required this.accent2,
    required this.ground,
    required this.drift,
    required this.particle,
    required this.rule,
    required this.blurb,
    this.lifeMultiplier = 1,
    this.everyoneGlows = false,
    this.freezeChance = .55,
  });

  final String id, name, when, rule, blurb;
  final int daysAway;
  final Color accent, accent2, particle;
  final List<Color> ground;
  final Drift drift;

  /// Rules that actually bend, not just colour.
  final double lifeMultiplier;
  final bool everyoneGlows;
  final double freezeChance;

  bool get isNightly => id == 'nightly';
}

const kBlooms = <Bloom>[
  Bloom(
    id: 'nightly',
    name: 'NIGHTLY',
    when: 'every night, dusk to dawn',
    daysAway: 0,
    accent: Color(0xFF6FF3CE),
    accent2: Color(0xFFBFE9FF),
    ground: [Color(0xFF0B1724), Color(0xFF071019), Color(0xFF04070D), Color(0xFF020408)],
    drift: Drift.plankton,
    particle: Color(0xFFA0E1EB),
    rule: 'Whispers burn 22 seconds. Glow resets at dawn.',
    blurb: 'The ordinary dark. Open it on the walk home, catch three things, lose them all.',
  ),
  Bloom(
    id: 'exam',
    name: 'EXAM BLOOM',
    when: 'finals week · 7 nights',
    daysAway: 12,
    accent: Color(0xFFFFB347),
    accent2: Color(0xFFFF7A45),
    ground: [Color(0xFF1C1307), Color(0xFF140D05), Color(0xFF0A0703), Color(0xFF050301)],
    drift: Drift.ember,
    particle: Color(0xFFFFC88C),
    rule: 'Whispers burn 3× longer. Everyone gets Still Water.',
    blurb: 'Seven nights of collective panic. Nothing fades fast because nobody is sleeping anyway.',
    lifeMultiplier: 3,
  ),
  Bloom(
    id: 'holi',
    name: 'HOLI BLOOM',
    when: 'one day, once a year',
    daysAway: 41,
    accent: Color(0xFFFF4FA3),
    accent2: Color(0xFF7CE86A),
    ground: [Color(0xFF1D0A1E), Color(0xFF150715), Color(0xFF0A040B), Color(0xFF050205)],
    drift: Drift.pigment,
    particle: Color(0xFFFF78BE),
    rule: 'Every whisper carries pigment. A boost detonates in colour.',
    blurb: 'The only night the dark is not dark. The map is thrown in fistfuls.',
  ),
  Bloom(
    id: 'diwali',
    name: 'DIWALI BLOOM',
    when: 'five nights',
    daysAway: 73,
    accent: Color(0xFFFFD36B),
    accent2: Color(0xFFFF8A4C),
    ground: [Color(0xFF1B1207), Color(0xFF150E06), Color(0xFF0B0703), Color(0xFF050301)],
    drift: Drift.lantern,
    particle: Color(0xFFFFCE8C),
    rule: 'The whole campus glows at maximum. Nobody is dim tonight.',
    blurb: 'Everyone is bright, so status means nothing and people just talk. '
        'It is the kindest night of the year.',
    everyoneGlows: true,
  ),
  Bloom(
    id: 'monsoon',
    name: 'MONSOON BLOOM',
    when: 'first heavy rain',
    daysAway: 96,
    accent: Color(0xFF7FA8FF),
    accent2: Color(0xFFB7A8FF),
    ground: [Color(0xFF0A1123), Color(0xFF070C19), Color(0xFF040710), Color(0xFF020409)],
    drift: Drift.rain,
    particle: Color(0xFFAAC8FF),
    rule: 'Rain scatters your ring. Hunters lose you twice as often.',
    blurb: 'Nobody outside, everybody online. The best hiding night there is.',
    freezeChance: .8,
  ),
  Bloom(
    id: 'snow',
    name: 'FIRST SNOW',
    when: 'the night it first sticks',
    daysAway: 134,
    accent: Color(0xFFDCEEFF),
    accent2: Color(0xFF9FC6E8),
    ground: [Color(0xFF0E1824), Color(0xFF0B131E), Color(0xFF070D15), Color(0xFF03060B)],
    drift: Drift.snow,
    particle: Color(0xFFEBF6FF),
    rule: 'Everything slows. Whispers drift instead of decaying.',
    blurb: 'It gets called at 2am by whoever is awake first, and the whole campus wakes up for it.',
    lifeMultiplier: 2,
  ),
];

/// Pigment thrown on a Holi night.
const kPigments = <Color>[
  Color(0xFFFF4FA3),
  Color(0xFF7CE86A),
  Color(0xFFFFD36B),
  Color(0xFF78BEFF),
];
