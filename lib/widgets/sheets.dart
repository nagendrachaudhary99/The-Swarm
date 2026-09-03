import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/whisper_pool.dart';
import '../data/swarm_api.dart';
import '../engine/swarm_engine.dart';
import '../models/bloom.dart';
import '../models/swarm_class.dart';
import '../models/whisper.dart';
import '../theme.dart';

Future<void> _sheet(BuildContext context, Widget Function(BuildContext) body) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8020408),
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .86),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF101927), Color(0xFF070B12)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Color(0x3D6FF3CE))),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              body(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _title(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(s.toUpperCase(),
          style: Swarm.data(size: 9.5, color: Swarm.plankton, tracking: 2.4)),
    );

Widget _lede(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(s, style: Swarm.voice(size: 14, color: Swarm.fog)),
    );

Widget _row(String key, String head, String copy) => Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Swarm.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(key.toUpperCase(),
                  style: Swarm.data(size: 8.5, color: Swarm.murk, tracking: 1.5)),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(head, style: Swarm.display(size: 12.5, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(copy, style: Swarm.voice(size: 12.4, color: Swarm.fog)),
            ]),
          ),
        ],
      ),
    );

Widget _button(String label, VoidCallback onTap, {bool ghost = false}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: ghost ? Swarm.line : Swarm.plankton.withValues(alpha: .42)),
            color: ghost ? null : Swarm.plankton.withValues(alpha: .1),
          ),
          child: Text(label.toUpperCase(),
              style: Swarm.data(
                  size: 10, color: ghost ? Swarm.fog : Swarm.plankton, tracking: 2)),
        ),
      ),
    );

// ------------------------------------------------------------------- sheets

Future<void> showClassSheet(BuildContext context, SwarmEngine engine) =>
    _sheet(context, (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title('Your class tonight'),
              _lede('Classes are dealt at each emergence and last until the brood '
                  'goes under. You do not pick who you are — you pick what you do with it.'),
              Row(
                children: [
                  for (final c in SwarmClass.values) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          engine.setClass(c);
                          setLocal(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                          margin: EdgeInsets.only(right: c == SwarmClass.mage ? 0 : 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: engine.cls == c
                                  ? c.color.withValues(alpha: .55)
                                  : Swarm.line,
                            ),
                            color: engine.cls == c ? c.color.withValues(alpha: .09) : null,
                          ),
                          child: Column(children: [
                            Icon(c.icon, size: 22, color: c.color),
                            const SizedBox(height: 6),
                            Text(c.label,
                                style: Swarm.display(size: 11.5, color: c.color, weight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(c.ability,
                                textAlign: TextAlign.center,
                                style: Swarm.data(size: 8, color: Swarm.murk, tracking: 1)),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(engine.cls.blurb, style: Swarm.voice(size: 14, color: Swarm.fog)),
              _button('Close', () => Navigator.pop(ctx), ghost: true),
            ],
          ),
        ));

Future<void> showInfoSheet(BuildContext context) => _sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('How the swarm works'),
          _lede('Four rules. Nothing else to learn.'),
          _row('01', 'It is asleep almost always',
              'The app unlocks for 24 hours at a time, a handful of nights a year — the night '
                  'before finals, first snow, the last home game. Everyone is inside at once or not at all.'),
          _row('02', 'There is no feed',
              'Press PING and a sonar sweep reveals whispers around you. They decay in about '
                  'twenty seconds. If you did not catch it, it did not happen.'),
          _row('03', 'Glow is earned nightly',
              'Boosts brighten you, silence dims you. Cross 80 and the Deep Ocean opens, '
                  'where the actually useful secrets live.'),
          _row('Live', SwarmApi.ready && SwarmApi.instance.signedIn
                  ? 'Signed in · ${SwarmApi.instance.user?.email ?? 'this device'}'
                  : 'Offline · running on the local pool',
              SwarmApi.ready && SwarmApi.instance.signedIn
                  ? 'You stay signed in on this device until you sign out. Whispers you '
                      'catch are real ones from the campus.'
                  : 'No account, no network — the app still works, it just plays against '
                      'the offline pool.'),
          _row('04', 'The ring pops',
              'Track a whisper and a ring shows how far, never where. Inside 10 metres it bursts '
                  'and tells you nothing. Look up. They are in this room. That is as close as the app will ever take you.'),
          _button('Got it', () => Navigator.pop(ctx), ghost: true),
          if (SwarmApi.ready && SwarmApi.instance.signedIn)
            _button('Sign out', () async {
              await SwarmApi.instance.signOut();
              if (ctx.mounted) Navigator.pop(ctx);
            }, ghost: true),
        ],
      ),
    );

Future<void> showDeepSheet(BuildContext context, SwarmEngine engine) => _sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Deep ocean · glow 80+'),
          _lede(engine.deepUnlocked
              ? 'You are bright enough to be down here. These do not decay for an hour.'
              : 'You are at ${engine.glow.round()} glow. Boost whispers and post your own to get to 80.'),
          for (final d in deepPool)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Swarm.plankton.withValues(alpha: .16)),
                  color: Swarm.plankton.withValues(alpha: .04),
                ),
                child: engine.deepUnlocked
                    ? Text(d, style: Swarm.voice(size: 12.8))
                    : ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Opacity(
                          opacity: .5,
                          child: Text(d, style: Swarm.voice(size: 12.8)),
                        ),
                      ),
              ),
            ),
          if (!engine.deepUnlocked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('● SEALED UNTIL YOU GLOW',
                  textAlign: TextAlign.center,
                  style: Swarm.data(size: 9, color: Swarm.murk, tracking: 2)),
            ),
          _button('Close', () => Navigator.pop(ctx), ghost: true),
        ],
      ),
    );

Future<void> showWhisperSheet(BuildContext context, SwarmEngine engine) {
  final controller = TextEditingController();
  return _sheet(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Drop a whisper'),
          _lede('It lands where you are standing and burns out in '
              '${engine.megaphoneOn ? 52 : 26} seconds. No name, no handle, no history.'),
          TextField(
            controller: controller,
            maxLength: 140,
            maxLines: 4,
            autofocus: true,
            onChanged: (_) => setLocal(() {}),
            style: Swarm.voice(size: 14),
            cursorColor: Swarm.plankton,
            decoration: InputDecoration(
              hintText: 'say the thing you would only say in the dark…',
              hintStyle: Swarm.voice(size: 14, color: Swarm.murk, italic: true),
              counterStyle: Swarm.data(size: 8.5, color: Swarm.murk),
              filled: true,
              fillColor: const Color(0xB304060B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Swarm.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Swarm.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Swarm.plankton.withValues(alpha: .45)),
              ),
            ),
          ),
          _button('Release into the dark', () {
            final v = controller.text.trim();
            if (v.isEmpty) return;
            engine.postWhisper(v);
            Navigator.pop(ctx);
          }),
          _button('Cancel', () => Navigator.pop(ctx), ghost: true),
        ],
      ),
    ),
  );
}

/// The payoff. No arrow, no name — four blurred people and what their bodies
/// are doing. Getting it right still only opens a door somebody else has to
/// walk through.
Future<void> showMirageSheet(BuildContext context, SwarmEngine engine, Whisper popped) {
  final rng = Random();
  final bodies = List<String>.from(bodyLanguage)..shuffle(rng);
  final four = bodies.take(4).toList();
  final right = rng.nextInt(4);
  const hues = [Color(0xFF2A3D52), Color(0xFF3A2F4E), Color(0xFF25404A), Color(0xFF43323A)];

  return _sheet(
    context,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Quantum mirage · ring popped'),
        _lede('The signal died at 9 metres. It will not come back. They are in this '
            'room, looking at their phone exactly like you are.'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 1.1,
          children: [
            for (var i = 0; i < 4; i++)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _resolve(context, engine, i == right, rng);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Swarm.line),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                        child: Container(
                          width: 46,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [hues[i], const Color(0xFF0C1420)],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(22),
                              bottom: Radius.circular(9),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(four[i],
                          textAlign: TextAlign.center,
                          style: Swarm.voice(size: 11.5, color: Swarm.fog, italic: true)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        _button('Leave a spore instead · walk away first', () {
          engine.dropSpore();
          Navigator.pop(ctx);
        }),
        _button('Let them stay hidden', () => Navigator.pop(ctx), ghost: true),
      ],
    ),
  );
}

void _resolve(BuildContext context, SwarmEngine engine, bool correct, Random rng) {
  if (!correct) {
    _sheet(
      context,
      (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('Wrong signal'),
        _lede('Not them. By the time you looked up they had gone out the north door, '
            'and the ring is gone for good.'),
        _button('Close', () => Navigator.pop(ctx), ghost: true),
      ]),
    );
    return;
  }

  engine.addGlow(6);
  final accepted = rng.nextDouble() < .62;

  _sheet(
    context,
    (ctx) => accepted
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title('Face-off · both said yes'),
            _lede('You both tapped inside the same minute. This is everything the app '
                'will ever reveal, and only because two people agreed to it.'),
            _row('Major', majors[rng.nextInt(majors.length)],
                '${years[rng.nextInt(years.length)]} · ${dorms[rng.nextInt(dorms.length)]}'),
            _row('Then', 'The chat opens for 10 minutes',
                'No usernames, no photos, no history. When it closes it is deleted. If you '
                    'want more you have to say so out loud, in the room, like a person.'),
            _button('Close', () => Navigator.pop(ctx), ghost: true),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _title('They declined'),
            _lede('You guessed right, and they said no. That is allowed — it is the whole '
                'point. The lock is permanent for tonight.'),
            _button('Close', () => Navigator.pop(ctx), ghost: true),
          ]),
  );
}


// ------------------------------------------------------- blooms & behaviour

Future<void> showBloomSheet(BuildContext context, SwarmEngine engine) =>
    _sheet(context, (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title('The bloom calendar'),
              _lede('The Swarm is awake every night, dusk to dawn. A few nights a year '
                  'it blooms — exams, festivals, first snow — and the whole world changes '
                  'colour and bends its own rules. Tap one to walk into it.'),
              for (final b in kBlooms)
                GestureDetector(
                  onTap: () {
                    engine.setBloom(b);
                    setLocal(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: engine.bloom.id == b.id
                            ? b.accent.withValues(alpha: .58)
                            : Swarm.line,
                      ),
                      color: engine.bloom.id == b.id
                          ? b.accent.withValues(alpha: .10)
                          : null,
                    ),
                    child: Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: b.accent,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: b.accent, blurRadius: 11)],
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.name,
                                style: Swarm.display(
                                    size: 12, color: b.accent, weight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(b.rule, style: Swarm.voice(size: 12, color: Swarm.fog)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        engine.bloom.id == b.id
                            ? 'LIVE'
                            : b.daysAway == 0 ? 'TONIGHT' : 'IN ${b.daysAway}D',
                        style: Swarm.data(
                            size: 8,
                            color: engine.bloom.id == b.id ? b.accent : Swarm.murk,
                            tracking: 1.4),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 6),
              Text(engine.bloom.blurb, style: Swarm.voice(size: 14, color: Swarm.fog)),
              _button('Close', () => Navigator.pop(ctx), ghost: true),
            ],
          ),
        ));

Future<void> showRitualSheet(BuildContext context, SwarmEngine engine) => _sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Tonight’s rituals'),
          _lede('Three small things. Finish them and the night is complete — your streak '
              'is safe and the app stops asking anything of you. It resets at dawn '
              'whether you come back or not.'),
          for (final r in engine.rituals)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Swarm.line)),
              ),
              child: Row(children: [
                Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: r.done ? Swarm.plankton.withValues(alpha: .5) : Swarm.line),
                    color: r.done ? Swarm.plankton.withValues(alpha: .14) : null,
                  ),
                  child: r.done
                      ? const Icon(Icons.check, size: 12, color: Swarm.plankton)
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.label,
                        style: Swarm.display(
                            size: 12,
                            weight: FontWeight.w700,
                            color: r.done ? Swarm.plankton : Swarm.foam)),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: LinearProgressIndicator(
                        value: r.progress,
                        minHeight: 2,
                        backgroundColor: Colors.white.withValues(alpha: .08),
                        valueColor: const AlwaysStoppedAnimation(Swarm.plankton),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                Text('${r.value}/${r.goal} · +${r.reward}',
                    style: Swarm.data(size: 8.5, color: Swarm.murk)),
              ]),
            ),
          const SizedBox(height: 14),
          Text(
            'Streak: ${engine.streak} nights. You have ${engine.shield} shield, which '
            'covers one missed night automatically. Nobody should have to open an app '
            'at 3am to protect a number.',
            style: Swarm.voice(size: 13.5, color: Swarm.fog),
          ),
          _button('Close', () => Navigator.pop(ctx), ghost: true),
        ],
      ),
    );

Future<void> showStatSheet(BuildContext context, SwarmEngine e, String which) => _sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (which) {
          'streak' => [
              _title('Your streak'),
              _lede('${e.streak} nights. A night counts when you finish the three '
                  'rituals — not for opening the app, and not for time spent in it.'),
              _row('Shield', '${e.shield} in reserve',
                  'One missed night is absorbed automatically. A streak should be a '
                      'memory of a habit, not a hostage.'),
              _row('Reset', 'Everything goes at dawn',
                  'Glow, whispers, rituals, your class. Only the streak carries. '
                      'Tomorrow night everybody starts level again.'),
            ],
          'pulse' => [
              _title('Campus pulse'),
              _lede('${e.pulse} people have this open right now. About '
                  '${(e.pulse * 0.14).round()} are within 200 metres of you.'),
              _row('Peak', '11:40pm – 1:20am',
                  'Two thirds of a night’s whispers land in those hundred minutes. The '
                      'app is busiest exactly when people are least able to sleep.'),
            ],
          _ => [
              _title('What you missed'),
              _lede('${e.missed} whispers died within 200 metres of you tonight, unheard. '
                  'They are gone — not archived, not recoverable, not anywhere.'),
              _row('Why', 'The sweep is the only way in',
                  'Nothing is ever pushed to you. A whisper you did not ping for is a '
                      'whisper that happened to somebody else.'),
              _row('Note', 'This number is not a debt',
                  'It resets at dawn with everything else. It is here to tell you the '
                      'campus is alive, not to make you feel behind.'),
            ],
        }..add(_button('Close', () => Navigator.pop(ctx), ghost: true)),
      ),
    );

/// Peak-end: people judge a night by its best moment and its ending, so the
/// night ends on your own best line rather than on an empty feed.
Future<void> showDawnReport(BuildContext context, SwarmEngine e) => _sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 78,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFB347), Color(0xFFFF6B4A), Color(0xFF2A1A1F)],
                stops: [0, .4, 1],
              ),
            ),
          ),
          Text('Dawn.', style: Swarm.display(size: 26)),
          const SizedBox(height: 6),
          Text(
            'The water is empty again. ${e.missed} whispers died out there tonight and '
            'every one of them is gone for good.',
            style: Swarm.voice(size: 14, color: Swarm.fog),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _tile('${e.caught}', 'caught'),
            const SizedBox(width: 8),
            _tile('${e.given}', 'brightened'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _tile('${e.peakGlow.round()}', 'peak glow'),
            const SizedBox(width: 8),
            _tile(e.closest > 900 ? '—' : '${e.closest.round()}m', 'closest'),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Swarm.bard.withValues(alpha: .3)),
              color: Swarm.bard.withValues(alpha: .06),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('THE ONE YOU KEPT',
                  style: Swarm.data(size: 8, color: Swarm.bard, tracking: 2.4)),
              const SizedBox(height: 7),
              Text(
                '“${e.bestCatch ?? 'you did not catch anything tonight. the dark was quiet.'}”',
                style: Swarm.voice(size: 13.5),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _tile('${e.streak}', 'night streak'),
            const SizedBox(width: 8),
            _tile('${kBlooms[1].daysAway}', 'days to next bloom'),
          ]),
          _button('Back into the dark', () => Navigator.pop(ctx)),
          const SizedBox(height: 14),
          Text(
            'Nothing here carries into tomorrow except the streak. That is the point.',
            textAlign: TextAlign.center,
            style: Swarm.voice(size: 12.5, color: Swarm.murk),
          ),
        ],
      ),
    );

Widget _tile(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Swarm.line),
          color: Colors.white.withValues(alpha: .02),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: Swarm.data(size: 20, color: Swarm.foam, weight: FontWeight.w700, tracking: -.4)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              style: Swarm.data(size: 8, color: Swarm.murk, tracking: 1.6)),
        ]),
      ),
    );
