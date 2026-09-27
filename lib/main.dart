import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'config.dart';
import 'data/swarm_api.dart';
import 'painters/sonar_painter.dart';
import 'screens/emergence_screen.dart';
import 'screens/gate_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Swarm.abyss,
  ));
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SonarPainter.warmUp(); // bake the grain tile once

  // The app is fully playable with no network — it just runs on the offline
  // pool instead of the campus. Connection is an upgrade, never a gate.
  try {
    await SwarmApi.connect();
  } catch (_) {/* offline is a valid way to run */}

  runApp(const SwarmApp());
}

/// Ask the phone where it is; fall back to the pilot campus with a small
/// scatter so two windows on one laptop are not standing in the same spot.
/// [real] says whether this came from the device or from the pilot fallback.
/// It matters because the fallback is RANDOM: re-rolling it on a refresh would
/// teleport a standing person across the campus every twenty seconds.
Future<({double lat, double lon, bool real})> whereAmI() async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse) {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      return (lat: p.latitude, lon: p.longitude, real: true);
    }
  } catch (_) {/* desktop, web without permission, simulator */}

  // Scatter, so two windows on one laptop are not standing on the same pixel —
  // but scatter that FITS INSIDE A SWEEP.
  //
  // This was ±0.001°, which is ±111 m, applied independently to each client.
  // Two people with location off could therefore land 311 m apart while
  // sitting at the same table, and the sweep only reaches 140 m. It was random
  // per page load, so the app worked, then didn't, then did, with nothing on
  // screen to explain any of it — the worst kind of broken.
  //
  // ±0.00025° is ±28 m, so the worst case is 78 m apart: always inside the
  // opening lens, still far enough to read as a real distance rather than as
  // the ten-metre floor.
  const spread = 0.0005; // (rand - .5) * spread  ->  ±0.00025°
  final r = Random();
  return (
    lat: Config.fallbackLat + (r.nextDouble() - .5) * spread,
    lon: Config.fallbackLon + (r.nextDouble() - .5) * spread,
    real: false,
  );
}

class SwarmApp extends StatelessWidget {
  const SwarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Swarm',
      debugShowCheckedModeBanner: false,
      theme: Swarm.theme(),
      home: const _Root(),
    );
  }
}


/// Gate first, sonar after. If Supabase never connected we skip the door
/// entirely and run on the offline pool — the app is playable with no account.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  StreamSubscription<AuthState>? _sub;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    if (!SwarmApi.ready) {
      _restoring = false;
      return;
    }
    // Supabase reads the stored session from disk *after* initialize()
    // returns. Building on the synchronous value flashed the sign-in screen at
    // people who were already signed in — which is exactly what makes an app
    // feel like it logs you out every time.
    _sub = SwarmApi.instance.authChanges.listen((_) {
      if (mounted) setState(() => _restoring = false);
    });
    SwarmApi.instance.restoreSession().then((_) {
      if (mounted) setState(() => _restoring = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        backgroundColor: Swarm.abyss,
        body: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: Swarm.plankton),
          ),
        ),
      );
    }
    if (!Config.demo && SwarmApi.ready && !SwarmApi.instance.signedIn) {
      return GateScreen(onIn: () => setState(() {}));
    }
    return const EmergenceScreen();
  }
}
