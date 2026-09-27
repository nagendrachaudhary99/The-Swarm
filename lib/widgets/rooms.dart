import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/swarm_api.dart';
import '../models/room.dart';
import '../theme.dart';
import 'sheets.dart' show swarmSheet;

/// Distance has one colour vocabulary in this app and this is it. A room at
/// `hot` and a whisper at `hot` are the same orange, because they are the same
/// fact — the server computed both with the same ladder.
Color bandColour(String band) => switch (band) {
      'mirage' || 'critical' => Swarm.critical,
      'hot' => Swarm.hot,
      'warm' => Swarm.warm,
      _ => Swarm.cold,
    };

String _left(Duration d) {
  if (d.isNegative) return 'gone';
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  return '${d.inHours}h';
}

/// Turn whatever Postgres raised into something a person can act on. The
/// server's messages are precise and unfriendly on purpose; this is the only
/// place that translates them.
String humanise(Object e) {
  final s = e.toString();
  if (s.contains('out of range')) {
    return 'You are not close enough. Walk toward it — the door is physical, '
        'and the check is the server\'s, not the button\'s.';
  }
  if (s.contains('already have a room open')) {
    return 'You already have a room open. Close that one first — one at a time.';
  }
  if (s.contains('blocked by filter')) return 'That will not go through.';
  if (s.contains('rate_limit')) return 'Slow down a moment.';
  if (s.contains('not in this room')) return 'You left this room.';
  if (s.contains('no such room')) return 'That room is gone.';
  if (s.contains('no beacon')) {
    return 'The app does not know where you are yet. Give it a moment.';
  }
  if (s.contains('muted until')) return 'You are muted for now.';
  if (s.contains('suspended')) return 'This account is suspended.';
  return s;
}

// ------------------------------------------------------------------- rooms

Future<void> showRoomsSheet(BuildContext context) =>
    swarmSheet(context, (_) => const _Rooms());

class _Rooms extends StatefulWidget {
  const _Rooms();
  @override
  State<_Rooms> createState() => _RoomsState();
}

class _RoomsState extends State<_Rooms> {
  final _title = TextEditingController();
  List<Room>? _rooms;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Rooms open and die while you are looking at the list. Ten seconds is
    // often enough to feel live and rare enough not to be a drain.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!SwarmApi.ready || !SwarmApi.instance.signedIn) {
      if (mounted) setState(() => _rooms = const []);
      return;
    }
    try {
      final r = await SwarmApi.instance.roomsNear();
      if (mounted) setState(() => _rooms = r);
    } catch (e) {
      if (mounted) setState(() => _error = humanise(e));
    }
  }

  Future<void> _open() async {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await SwarmApi.instance.openRoom(t);
      _title.clear();
      await _load();
      if (!mounted) return;
      Room? room;
      for (final r in _rooms ?? const <Room>[]) {
        if (r.id == id) room = r;
      }
      if (room != null) {
        Navigator.of(context).pop();
        await showChatSheet(context, room);
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanise(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enter(Room room) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SwarmApi.instance.joinRoom(room.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      await showChatSheet(context, room);
    } catch (e) {
      if (mounted) setState(() => _error = humanise(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ROOMS IN RANGE',
            style: Swarm.data(size: 9.5, color: Swarm.plankton, tracking: 2.4)),
        const SizedBox(height: 6),
        Text(
          'A room is somewhere to actually talk. You can see one from further '
          'than you can enter it — the walk is the point.',
          style: Swarm.voice(size: 14, color: Swarm.fog),
        ),
        const SizedBox(height: 16),
        if (rooms == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6, color: Swarm.plankton),
              ),
            ),
          )
        else if (rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Nothing open near you. Open one and it appears on everyone '
              'else\'s radar as a band — never as a pin.',
              textAlign: TextAlign.center,
              style: Swarm.voice(size: 13, color: Swarm.murk),
            ),
          )
        else
          for (final r in rooms) _RoomRow(room: r, onEnter: () => _enter(r)),
        const SizedBox(height: 18),
        Container(height: 1, color: Swarm.line),
        const SizedBox(height: 16),
        Text('OPEN ONE HERE',
            style: Swarm.data(size: 9.5, color: Swarm.plankton, tracking: 2.4)),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          maxLength: 60,
          style: Swarm.voice(size: 15),
          cursorColor: Swarm.plankton,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _busy ? null : _open(),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'what is it about?',
            hintStyle: Swarm.voice(size: 15, color: Swarm.murk),
            filled: true,
            fillColor: const Color(0xB3050A12),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: _border(Swarm.line),
            enabledBorder: _border(Swarm.line),
            focusedBorder: _border(Swarm.plankton.withValues(alpha: .5)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: Swarm.voice(size: 12.8, color: Swarm.rogue)),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _busy ? null : _open,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Swarm.plankton.withValues(alpha: _busy ? .04 : .1),
              border: Border.all(
                  color: Swarm.plankton.withValues(alpha: _busy ? .2 : .42)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.6, color: Swarm.plankton))
                : Text('OPEN THE ROOM',
                    style: Swarm.data(
                        size: 10, color: Swarm.plankton, tracking: 2)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'It stays open an hour, then it and everything said in it are '
          'deleted. Not archived.',
          textAlign: TextAlign.center,
          style: Swarm.voice(size: 11.6, color: Swarm.murk),
        ),
      ],
    );
  }
}

OutlineInputBorder _border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.onEnter});
  final Room room;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final c = bandColour(room.band);
    // Out of range is shown, not hidden. Knowing something is happening you
    // cannot reach yet is the whole feeling the app is for.
    final reachable = room.inRange || room.joined;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: Swarm.silt.withValues(alpha: .55),
        border: Border.all(color: c.withValues(alpha: reachable ? .38 : .16)),
      ),
      child: Row(
        children: [
          Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 11),
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Swarm.voice(
                        size: 14.5,
                        color: reachable ? Swarm.foam : Swarm.fog)),
                const SizedBox(height: 4),
                Text(
                  '${room.band.toUpperCase()} · ${room.members} '
                  '${room.members == 1 ? 'VOICE' : 'VOICES'} · ${_left(room.remaining)} LEFT',
                  style: Swarm.data(size: 8.5, color: Swarm.murk, tracking: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: reachable ? onEnter : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: reachable ? c.withValues(alpha: .12) : null,
                border: Border.all(
                    color: reachable ? c.withValues(alpha: .5) : Swarm.line),
              ),
              child: Text(
                room.joined ? 'ENTER' : (reachable ? 'JOIN' : 'TOO FAR'),
                style: Swarm.data(
                    size: 9,
                    color: reachable ? c : Swarm.murk,
                    tracking: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- chat

Future<void> showChatSheet(BuildContext context, Room room) =>
    swarmSheet(context, (_) => _Chat(room: room));

class _Chat extends StatefulWidget {
  const _Chat({required this.room});
  final Room room;
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _say = TextEditingController();
  final _scroll = ScrollController();
  final _lines = <ChatLine>[];
  RealtimeChannel? _channel;
  String? _error;
  bool _busy = false, _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime, not polling. The RLS policy on `messages` is what makes this
    // safe: a non-member's socket is sent nothing, because the row is refused
    // upstream rather than filtered here.
    _channel = SwarmApi.instance.liveRoom(widget.room.id, (line) {
      if (!mounted) return;
      if (_lines.any((l) => l.id == line.id)) return; // our own echo
      setState(() => _lines.add(line));
      _toBottom();
    });
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) SwarmApi.instance.drop(ch);
    _say.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final h = await SwarmApi.instance.history(widget.room.id);
      if (!mounted) return;
      setState(() {
        _lines
          ..clear()
          ..addAll(h);
        _loading = false;
      });
      _toBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = humanise(e);
          _loading = false;
        });
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final body = _say.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SwarmApi.instance.say(widget.room.id, body);
      _say.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = humanise(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _silence(ChatLine line) async {
    try {
      await SwarmApi.instance.blockSpeaker(line.id);
      if (mounted) setState(() => _lines.removeWhere((l) => l.handle == line.handle));
    } catch (_) {/* blocking is best-effort; never a dialog */}
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.room.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Swarm.data(
                      size: 9.5, color: Swarm.plankton, tracking: 2.4)),
            ),
            Text('${_left(widget.room.remaining)} LEFT',
                style: Swarm.data(size: 8.5, color: Swarm.murk, tracking: 1.3)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Everyone here is a handle. Yours means nothing outside this room, '
          'and all of it is deleted when the room closes.',
          style: Swarm.voice(size: 12.4, color: Swarm.murk),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: h * .42,
          child: _loading
              ? const Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6, color: Swarm.plankton)))
              : _lines.isEmpty
                  ? Center(
                      child: Text('Nobody has said anything yet.',
                          style: Swarm.voice(size: 13, color: Swarm.murk)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.zero,
                      itemCount: _lines.length,
                      itemBuilder: (_, i) => _Bubble(
                        line: _lines[i],
                        onSilence: () => _silence(_lines[i]),
                      ),
                    ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: Swarm.voice(size: 12.6, color: Swarm.rogue)),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _say,
                maxLength: 240,
                minLines: 1,
                maxLines: 3,
                style: Swarm.voice(size: 15),
                cursorColor: Swarm.plankton,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'say something',
                  hintStyle: Swarm.voice(size: 15, color: Swarm.murk),
                  filled: true,
                  fillColor: const Color(0xB3050A12),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: _border(Swarm.line),
                  enabledBorder: _border(Swarm.line),
                  focusedBorder: _border(Swarm.plankton.withValues(alpha: .5)),
                ),
              ),
            ),
            const SizedBox(width: 9),
            GestureDetector(
              onTap: _send,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Swarm.plankton.withValues(alpha: .12),
                  border:
                      Border.all(color: Swarm.plankton.withValues(alpha: .45)),
                ),
                child: Text('SAY',
                    style: Swarm.data(
                        size: 10, color: Swarm.plankton, tracking: 2)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            await SwarmApi.instance.leaveRoom(widget.room.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text('LEAVE',
              textAlign: TextAlign.center,
              style: Swarm.data(size: 9, color: Swarm.murk, tracking: 1.8)),
        ),
      ],
    );
  }
}

/// One line. Long-press silences whoever said it — the same block the rest of
/// the app uses, which resolves the author inside Postgres and never returns
/// it, so you can mute someone without ever being told who they are.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.line, required this.onSilence});
  final ChatLine line;
  final VoidCallback onSilence;

  @override
  Widget build(BuildContext context) {
    final mine = line.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine ? null : onSilence,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * .72),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(13),
              topRight: const Radius.circular(13),
              bottomLeft: Radius.circular(mine ? 13 : 3),
              bottomRight: Radius.circular(mine ? 3 : 13),
            ),
            color: mine
                ? Swarm.plankton.withValues(alpha: .10)
                : Swarm.silt.withValues(alpha: .8),
            border: Border.all(
                color: mine
                    ? Swarm.plankton.withValues(alpha: .3)
                    : Swarm.line),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(mine ? 'YOU' : line.handle,
                  style: Swarm.data(
                      size: 8,
                      color: mine ? Swarm.plankton : Swarm.murk,
                      tracking: 1.4)),
              const SizedBox(height: 4),
              Text(line.body, style: Swarm.voice(size: 14.5)),
            ],
          ),
        ),
      ),
    );
  }
}
