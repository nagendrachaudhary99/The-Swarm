import 'dart:math';
import 'dart:ui';

/// A compact quad, measured in metres. Swap this for real OSM geometry
/// (flutter_map + OpenStreetMap tiles) when you go live — the painter and the
/// engine only ever speak metres, so nothing else has to change.
class Campus {
  static const Size world = Size(240, 442);

  static const buildings = <Building>[
    Building('MORROW LIBRARY', Rect.fromLTWH(16, 34, 86, 58)),
    Building('HOLBROOK DINING', Rect.fromLTWH(140, 26, 84, 52)),
    Building('THE QUAD', Rect.fromLTWH(30, 118, 158, 86), open: true),
    Building('PHYS SCI', Rect.fromLTWH(14, 236, 72, 74)),
    Building('GREER HALL', Rect.fromLTWH(118, 228, 100, 56)),
    Building('NORTH CART', Rect.fromLTWH(22, 336, 66, 38)),
    Building('STACKS ANNEX', Rect.fromLTWH(132, 326, 80, 52)),
  ];

  static const paths = <(Offset, Offset)>[
    (Offset(59, 92), Offset(59, 118)),
    (Offset(109, 161), Offset(182, 52)),
    (Offset(109, 204), Offset(109, 228)),
    (Offset(50, 204), Offset(50, 236)),
    (Offset(50, 310), Offset(55, 336)),
    (Offset(168, 284), Offset(172, 326)),
    (Offset(30, 161), Offset(16, 161)),
    (Offset(188, 161), Offset(224, 161)),
  ];
}

class Building {
  const Building(this.name, this.rect, {this.open = false});
  final String name;
  final Rect rect;

  /// Open ground (the quad) is drawn as a dashed outline, not a solid mass.
  final bool open;
}

/// Maps world metres to screen pixels. Owned by the screen, handed to both the
/// painter and the whisper bubbles so they never disagree about where a point is.
class MapTransform {
  const MapTransform(this.scale, this.origin);

  final double scale;
  final Offset origin;

  factory MapTransform.cover(Size view, Size world) {
    final scale = max(view.width / world.width, view.height / world.height);
    return MapTransform(
      scale,
      Offset(
        (view.width - world.width * scale) / 2,
        (view.height - world.height * scale) / 2,
      ),
    );
  }

  Offset toScreen(Offset world) => origin + world * scale;
  Offset toWorld(Offset screen) => (screen - origin) / scale;
}
