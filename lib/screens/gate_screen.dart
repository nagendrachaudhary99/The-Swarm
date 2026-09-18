import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../data/swarm_api.dart';
import '../theme.dart';

/// The front door. Campus email remains the membership test. Email/password
/// credentials are handled by Supabase Auth; the app never stores the password.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key, required this.onIn});

  final VoidCallback onIn;

  @override
  State<GateScreen> createState() => _GateScreenState();
}

enum _AuthMode { signIn, signUp }

class _GateScreenState extends State<GateScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final AnimationController _pulse;

  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _notice;
  StreamSubscription<String>? _refusals;

  bool get _creating => _mode == _AuthMode.signUp;

  @override
  void initState() {
    super.initState();
    _pulse =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();

    // OAuth addresses are known only after the provider returns. The API
    // applies the same campus-domain rule to that authenticated session and
    // reports a refusal here so the gate can explain what happened.
    _refusals = SwarmApi.instance.refusals.listen((email) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = null;
        _error = '$email is not a campus address. The Swarm is one college '
            'only — sign in with the account that college gave you.';
      });
    });
  }

  @override
  void dispose() {
    _refusals?.cancel();
    _pulse.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_creating) {
        final response = await SwarmApi.instance.signUpWithPassword(
          email: _email.text,
          password: _password.text,
        );

        if (!mounted) return;

        // When Supabase email confirmation is disabled, signup returns a
        // session immediately. When confirmation is enabled, the account is
        // created but there is no session until the address is confirmed.
        if (response.session != null) {
          widget.onIn();
        } else {
          setState(() {
            _mode = _AuthMode.signIn;
            _password.clear();
            _notice =
                'Account created. Check your college inbox to confirm your '
                'address, then come back and sign in with your password.';
          });
        }
      } else {
        await SwarmApi.instance.signInWithPassword(
          email: _email.text,
          password: _password.text,
        );

        if (mounted) widget.onIn();
      }
    } on CampusEmailRejected {
      if (mounted) {
        setState(() {
          _error =
              'The Swarm is one campus only. Use your college address — the '
              'domain is the whole door.';
        });
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();

      if (mounted) {
        setState(() {
          if (msg.contains('invalid login credentials') ||
              msg.contains('invalid_credentials')) {
            _error = 'That email/password combination did not match.';
          } else if (msg.contains('already registered') ||
              msg.contains('user_already_exists')) {
            _error =
                'That address already has an account. Switch to sign in.';
          } else if (msg.contains('password') &&
              (msg.contains('weak') || msg.contains('least'))) {
            _error = 'Use a stronger password and try again.';
          } else if (msg.contains('rate_limit') || msg.contains('429')) {
            _error = 'Too many attempts. Wait a bit and try again.';
          } else {
            _error = _creating
                ? 'Could not create that account.\n\n$e'
                : 'Could not sign in.\n\n$e';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await SwarmApi.instance.signInWith(OAuthProvider.google);

      // On web the page normally navigates away. On mobile the session comes
      // back through the configured deep link and the root handles it.
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Google would not open.\n\n$e';
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();

    if (email.isEmpty) {
      setState(() {
        _notice = null;
        _error = 'Enter your college email first.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await SwarmApi.instance.sendPasswordReset(email);

      if (mounted) {
        setState(() {
          _notice =
              'Password reset sent to $email. Open the recovery email to set '
              'a new password.';
        });
      }
    } on CampusEmailRejected {
      if (mounted) {
        setState(() {
          _error =
              'The Swarm is one campus only. Use your college address — the '
              'domain is the whole door.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not send the password reset.\n\n$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    if (_busy) return;

    setState(() {
      _mode = _creating ? _AuthMode.signIn : _AuthMode.signUp;
      _password.clear();
      _error = null;
      _notice = null;
      _obscurePassword = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Swarm.abyss,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) =>
                  CustomPaint(painter: _GatePainter(_pulse.value)),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'AWAKE EVERY NIGHT',
                          textAlign: TextAlign.center,
                          style: Swarm.data(
                            size: 9.5,
                            color: Swarm.murk,
                            tracking: 4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'THE SWARM',
                          textAlign: TextAlign.center,
                          style: Swarm.display(size: 44, tracking: -1.6),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _creating
                              ? 'Create an account with your college email and '
                                  'a password. Your campus domain is still the '
                                  'membership test.'
                              : 'One campus, no names. Sign in with your college '
                                  'email and password, or continue with Google.',
                          textAlign: TextAlign.center,
                          style: Swarm.voice(size: 14.5, color: Swarm.fog),
                        ),
                        const SizedBox(height: 26),
                        _googleButton(),
                        const SizedBox(height: 18),
                        _or(),
                        const SizedBox(height: 18),
                        _emailField(),
                        const SizedBox(height: 12),
                        _passwordField(),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style:
                                Swarm.voice(size: 12.8, color: Swarm.rogue),
                          ),
                        ],
                        if (_notice != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _notice!,
                            textAlign: TextAlign.center,
                            style:
                                Swarm.voice(size: 12.8, color: Swarm.fog),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _button(
                          _creating ? 'Create account' : 'Enter the dark',
                          _submit,
                        ),
                        if (!_creating) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _busy ? null : _forgotPassword,
                            child: Text(
                              'FORGOT PASSWORD?',
                              style: Swarm.data(
                                size: 9.5,
                                color: Swarm.murk,
                                tracking: 1.6,
                              ),
                            ),
                          ),
                        ],
                        TextButton(
                          onPressed: _busy ? null : _toggleMode,
                          child: Text(
                            _creating
                                ? 'ALREADY HAVE AN ACCOUNT? SIGN IN'
                                : 'NEW HERE? CREATE AN ACCOUNT',
                            textAlign: TextAlign.center,
                            style: Swarm.data(
                              size: 9.5,
                              color: Swarm.murk,
                              tracking: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'We keep your campus address for membership. Your '
                          'password is handled by Supabase Auth and is never '
                          'stored by this screen. No name, photo, contacts, or '
                          'history are required here.',
                          textAlign: TextAlign.center,
                          style: Swarm.voice(size: 11.8, color: Swarm.murk),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleButton() => GestureDetector(
        onTap: _busy ? null : _google,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: Swarm.foam.withValues(alpha: .05),
            border: Border.all(color: Swarm.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GoogleMark(),
              const SizedBox(width: 11),
              Text(
                'CONTINUE WITH GOOGLE',
                style: Swarm.data(size: 10.5, color: Swarm.fog, tracking: 2),
              ),
            ],
          ),
        ),
      );

  Widget _or() => Row(
        children: [
          Expanded(child: Container(height: 1, color: Swarm.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'OR',
              style: Swarm.data(size: 9, color: Swarm.murk, tracking: 2),
            ),
          ),
          Expanded(child: Container(height: 1, color: Swarm.line)),
        ],
      );

  Widget _emailField() => TextField(
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        style: Swarm.voice(size: 16),
        cursorColor: Swarm.plankton,
        decoration: _dec('you@yourcollege.edu'),
      );

  Widget _passwordField() => TextField(
        controller: _password,
        obscureText: _obscurePassword,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: [
          _creating ? AutofillHints.newPassword : AutofillHints.password,
        ],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (!_busy) _submit();
        },
        style: Swarm.voice(size: 16),
        cursorColor: Swarm.plankton,
        decoration: _dec(_creating ? 'create a password' : 'password').copyWith(
          suffixIcon: IconButton(
            onPressed: _busy
                ? null
                : () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Swarm.murk,
            ),
          ),
        ),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: Swarm.voice(size: 16, color: Swarm.murk),
        filled: true,
        fillColor: const Color(0xB3050A12),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
            border: Border.all(
              color: Swarm.plankton.withValues(alpha: _busy ? .2 : .45),
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: Swarm.plankton,
                  ),
                )
              : Text(
                  label.toUpperCase(),
                  style: Swarm.data(
                    size: 10.5,
                    color: Swarm.plankton,
                    tracking: 2.6,
                  ),
                ),
        ),
      );
}

/// Google's mark, drawn rather than fetched: one more asset is one more thing
/// that can fail to load on a dark screen at the moment someone is deciding
/// whether this app is real.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 15,
        height: 15,
        child: CustomPaint(painter: _GPainter()),
      );
}

class _GPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final stroke = size.width * .27;
    final arc = Rect.fromCircle(
      center: r.center,
      radius: (size.width - stroke) / 2,
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Four quadrants, then the bar that turns the ring into a G.
    canvas.drawArc(arc, -0.45, 1.30, false, p..color = _red);
    canvas.drawArc(arc, 0.85, 1.55, false, p..color = _yellow);
    canvas.drawArc(arc, 2.40, 1.55, false, p..color = _green);
    canvas.drawArc(arc, 3.95, 1.50, false, p..color = _blue);
    canvas.drawRect(
      Rect.fromLTRB(r.center.dx, r.center.dy - stroke / 2, r.right, r.center.dy + stroke / 2),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GPainter old) => false;
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
