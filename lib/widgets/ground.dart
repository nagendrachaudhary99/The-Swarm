import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config.dart';
import '../theme.dart';

/// The base layer under the sonar overlay.
///
/// Two interchangeable grounds: a real Google map when a key is supplied, and
/// the app's own drawn map when it is not. Everything above this — posts,
/// range rings, your own marker — is painted by [SonarPainter] either way, so
/// swapping the ground never touches the rest of the app.
///
/// Zoom is allowed. Panning and rotation are not, and the difference matters:
/// triangulation needs a BEARING, and dragging the map away from yourself is
/// what would eventually supply one. Zooming while pinned to your own position
/// reveals no direction at all — a post is drawn as a ring around you at every
/// scale — so it costs nothing and buys the thing the map is for: pull back and
/// only the loud whispers survive, lean in and the quiet ones appear.
class Ground extends StatelessWidget {
  const Ground({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom = 18,
    this.onZoom,
  });

  final double lat, lon;
  final double zoom;

  /// Fired as the camera settles, so the sweep can be re-cut to match.
  final ValueChanged<double>? onZoom;

  @override
  Widget build(BuildContext context) {
    if (!Config.hasMaps) return const SizedBox.expand();

    return ColorFiltered(
        // Pull the map down into the app's palette so the overlay stays the
        // brightest thing on screen.
        colorFilter: const ColorFilter.matrix(<double>[
          0.32, 0.28, 0.18, 0, -14,
          0.22, 0.34, 0.28, 0, -10,
          0.26, 0.30, 0.44, 0, 2,
          0, 0, 0, 1, 0,
      ]),
      child: GoogleMap(
        initialCameraPosition:
            CameraPosition(target: LatLng(lat, lon), zoom: zoom),
        mapType: MapType.normal,
        style: _darkStyle,
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
        scrollGesturesEnabled: false,   // no panning: that is where a bearing would come from
        zoomGesturesEnabled: true,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        liteModeEnabled: false,
        onCameraIdle: () {},
        onCameraMove: (pos) => onZoom?.call(pos.zoom),
      ),
    );
  }
}

/// Labels and points of interest are stripped out, not just dimmed: a shop
/// name next to a distance reading is a clue, and clues are what we are
/// promising not to give.
const _darkStyle = '''
[
 {"elementType":"geometry","stylers":[{"color":"#0d1018"}]},
 {"elementType":"labels","stylers":[{"visibility":"off"}]},
 {"featureType":"poi","stylers":[{"visibility":"off"}]},
 {"featureType":"transit","stylers":[{"visibility":"off"}]},
 {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1f2b"}]},
 {"featureType":"road","elementType":"labels","stylers":[{"visibility":"off"}]},
 {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#141a24"}]},
 {"featureType":"water","elementType":"geometry","stylers":[{"color":"#080b12"}]}
]
''';

/// Shown once, on top of the map, the first time someone opens the app.
class GroundNotice extends StatelessWidget {
  const GroundNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (Config.hasMaps) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        'DRAWN MAP · add GOOGLE_MAPS_KEY for the real one',
        style: Swarm.data(size: 7.5, color: Swarm.murk, tracking: 1.4),
      ),
    );
  }
}
