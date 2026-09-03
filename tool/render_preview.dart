// Renders the sonar to a PNG without a simulator, so the design can be
// reviewed on any machine:  flutter test tool/render_preview.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swarm/engine/swarm_engine.dart';
import 'package:swarm/models/campus.dart';
import 'package:swarm/painters/sonar_painter.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(File(p).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('render preview', (tester) async {
    await _loadFont('Syne', ['assets/fonts/Syne.ttf']);
    await _loadFont('Newsreader',
        ['assets/fonts/Newsreader.ttf', 'assets/fonts/Newsreader-Italic.ttf']);
    await _loadFont('JetBrainsMono', ['assets/fonts/JetBrainsMono.ttf']);
    await SonarPainter.warmUp();

    final e = SwarmEngine();
    e.ping();
    for (var i = 0; i < 70; i++) {
      e.update(1 / 60);
    }
    final w = e.whispers.firstWhere((x) => x.revealed)..anchor = const Offset(150, 300);
    e.track(w);
    for (var i = 0; i < 40; i++) {
      e.update(1 / 60);
    }

    const size = Size(390, 780);
    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    SonarPainter(engine: e, tf: MapTransform.cover(size, Campus.world), reduceMotion: false)
        .paint(canvas, size);
    final img = await recorder
        .endRecording()
        .toImage((size.width * scale).round(), (size.height * scale).round());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('preview.png').writeAsBytes(png!.buffer.asUint8List());
    stdout.writeln('wrote preview.png');
  });
}
