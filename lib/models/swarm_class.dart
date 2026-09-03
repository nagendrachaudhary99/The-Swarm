import 'package:flutter/material.dart';
import '../theme.dart';

/// Classes are dealt at each emergence and last until the brood goes under.
/// You do not pick who you are — you pick what you do with it.
enum SwarmClass { bard, rogue, mage }

extension SwarmClassX on SwarmClass {
  String get label => switch (this) {
        SwarmClass.bard => 'BARD',
        SwarmClass.rogue => 'ROGUE',
        SwarmClass.mage => 'MAGE',
      };

  String get ability => switch (this) {
        SwarmClass.bard => 'MEGAPHONE',
        SwarmClass.rogue => 'TRACK',
        SwarmClass.mage => 'STILL WATER',
      };

  Color get color => switch (this) {
        SwarmClass.bard => Swarm.bard,
        SwarmClass.rogue => Swarm.rogue,
        SwarmClass.mage => Swarm.mage,
      };

  IconData get icon => switch (this) {
        SwarmClass.bard => Icons.campaign_outlined,
        SwarmClass.rogue => Icons.my_location_outlined,
        SwarmClass.mage => Icons.ac_unit_outlined,
      };

  String get blurb => switch (this) {
        SwarmClass.bard =>
          'Every whisper on screen burns 60% longer, and yours burn double. '
              'Bards are the reason the night lasts.',
        SwarmClass.rogue =>
          'Turn a target ring into a directional wedge for 60 seconds. '
              'You still cannot see inside 10 metres. Nobody can.',
        SwarmClass.mage =>
          'Freeze decay for 20 seconds — nothing fades, nothing is lost — '
              'and cloak your own ring while it holds.',
      };

  double get cost => 34;
}
