import 'dart:math';

import 'package:flutter/material.dart';

import '../data/swarm_api.dart';
import '../theme.dart';

/// The front door. It asks for one thing — a campus address — because the
/// domain is the entire membership test. Nobody uploads an ID card, nobody
/// sends a photo, and we never learn a name.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key, required this.onIn});

  final VoidCallback onIn;

  @override
  State<GateScreen> createState() => _GateScreenState();
}

enum _Step { email, code }

class _GateScreenState extends State<GateScreen> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _code = TextEditingController();
  late final AnimationController _pulse;

  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SwarmApi.instance.sendCode(_email.text);
      if (mounted) setState(() => _step = _Step.code);
    } on CampusEmailRejected {
      if (mounted) {
        setState(() => _error =
            'The Swarm is one campus only. Use your college address — the '
            'domain is the whole door.');
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() => _error = msg.contains('rate_limit') || msg.contains('429')
            ? 'Too many mails from this campus in the last hour. Wait a bit, or '
                'tap “I already have a code” below if one was sent earlier.'
            : msg.contains('invalid')
                ? 'That mailbox could not be reached. Check the spelling — or if '
                    'you were given a code directly, use the link below.'
                : 'Could not send that.\n\n$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SwarmApi.instance.verifyCode(_email.text, _code.text);
      if (mounted) widget.onIn();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'That did not match. Paste the code, or the entire '
            'link from the mail — both expire after an hour, and clicking the link '
            'in your mail app spends it.\n\n$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onCode = _step == _Step.code;

    return Scaffold(
      backgroundColor: Swarm.abyss,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => CustomPaint(painter: _GatePainter(_pulse.value)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('AWAKE EVERY NIGHT',
                          textAlign: TextAlign.center,
                          style: Swarm.data(size: 9.5, color: Swarm.murk, tracking: 4)),
                      const SizedBox(height: 14),
                      Text('THE SWARM',
                          textAlign: TextAlign.center,
                          style: Swarm.display(size: 44, tracking: -1.6)),
                      const SizedBox(height: 14),
                      Text(
                        onCode
                            ? 'Paste the code for ${_email.text.trim()} — or the whole '
                                'link from the mail, either works. Both last one hour, '
                                'and opening the link in your mail app spends it.'
                            : 'One campus, no names, nothing kept. Your college address '
                                'is the only thing we check, and the only thing we store.',
                        textAlign: TextAlign.center,
                        style: Swarm.voice(size: 14.5, color: Swarm.fog),
                      ),
                      const SizedBox(height: 26),
                      if (!onCode) _emailField() else _codeField(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: Swarm.voice(size: 12.8, color: Swarm.rogue)),
                      ],
                      const SizedBox(height: 14),
                      _button(
                        onCode ? 'Enter the dark' : 'Send me a code',
                        onCode ? _verify : _send,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _step = onCode ? _Step.email : _Step.code;
                                  _code.clear();
                                  _error = null;
                                }),
                        child: Text(
                          onCode ? 'Use a different address' : 'I already have a code',
                          style: Swarm.data(size: 9.5, color: Swarm.murk, tracking: 1.6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'We store your address to prove you go here, and nothing else. '
                        'No name, no photo, no contacts, no history. Whispers are deleted '
                        'within the minute they die.',
                        textAlign: TextAlign.center,
                        style: Swarm.voice(size: 11.8, color: Swarm.murk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailField() => TextField(
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _busy ? null : _send(),
        style: Swarm.voice(size: 16),
        cursorColor: Swarm.plankton,
        decoration: _dec('you@yourcollege.edu'),
      );

  Widget _codeField() => TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.text,

        textAlign: TextAlign.center,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _busy ? null : _verify(),
        maxLines: 2,
        minLines: 1,
        style: Swarm.data(size: 15, color: Swarm.foam, weight: FontWeight.w700, tracking: 2),
        cursorColor: Swarm.plankton,
        decoration: _dec('paste the code, or the whole link').copyWith(counterText: ''),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: Swarm.voice(size: 16, color: Swarm.murk),
        filled: true,
        fillColor: const Color(0xB3050A12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: _border(Swarm.line),
        enabledBorder: _border(Swarm.line),
        focusedBorder: _border(Swarm.plankton.withValues(alpha: .5)),
      );

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: c),
      );

  Widget _button(String label, VoidCallback onTap) => GestureDetector(
        onTap: _busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: Swarm.plankton.withValues(alpha: _busy ? .05 : .12),
            border: Border.all(color: Swarm.plankton.withValues(alpha: _busy ? .2 : .45)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: Swarm.plankton),
                )
              : Text(label.toUpperCase(),
                  style: Swarm.data(size: 10.5, color: Swarm.plankton, tracking: 2.6)),
        ),
      );
}

/// A slow sweep behind the door, so the first screen already shows what the
/// app is: something listening in the dark.
class _GatePainter extends CustomPainter {
  _GatePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .38);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF0B1724), Color(0xFF05080E), Color(0xFF020408)],
          stops: [0, .5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: size.height)),
    );

    for (var i = 0; i < 4; i++) {
      final p = ((t + i / 4) % 1);
      canvas.drawCircle(
        c,
        p * size.width * .95,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Swarm.plankton.withValues(alpha: (1 - p) * .11),
      );
    }

    final r = Random(9);
    for (var i = 0; i < 40; i++) {
      final x = r.nextDouble() * size.width;
      final y = (r.nextDouble() * size.height - t * 40) % size.height;
      canvas.drawCircle(
        Offset(x, y),
        r.nextDouble() * 1.2 + .3,
        Paint()..color = const Color(0xFFA0E1EB).withValues(alpha: .10),
      );
    }
  }

  @override
  bool shouldRepaint(_GatePainter old) => old.t != t;
}
