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
Future<({double lat, double lon})> whereAmI() async {
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
      return (lat: p.latitude, lon: p.longitude);
    }
  } catch (_) {/* desktop, web without permission, simulator */}

  final r = Random();
  return (
    lat: Config.fallbackLat + (r.nextDouble() - .5) * 0.002,
    lon: Config.fallbackLon + (r.nextDouble() - .5) * 0.002,
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
    if (SwarmApi.ready && !SwarmApi.instance.signedIn) {
      return GateScreen(onIn: () => setState(() {}));
    }
    return const EmergenceScreen();
  }
}
