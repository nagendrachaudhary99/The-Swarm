import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/room.dart';

/// One whisper as the server is willing to describe it: a body and a distance
/// BAND. No coordinate, no author, no bearing. This class cannot represent a
/// position because the wire format has none.
class RemoteWhisper {
  RemoteWhisper({
    required this.id,
    required this.body,
    required this.klass,
    required this.boosts,
    required this.diesAt,
    required this.band,
  });

  factory RemoteWhisper.fromRow(Map<String, dynamic> r) => RemoteWhisper(
        id: r['id'] as String,
        body: r['body'] as String,
        klass: (r['klass'] ?? 'rogue') as String,
        boosts: (r['boosts'] ?? 0) as int,
        diesAt: DateTime.parse(r['dies_at'] as String),
        band: (r['band'] ?? 'cold') as String,
      );

  final String id, body, klass, band;
  final int boosts;
  final DateTime diesAt;

  Duration get remaining => diesAt.difference(DateTime.now());
  bool get dead => remaining.isNegative;

  /// The floor. The server said 'mirage', which means it refused to say more.
  bool get isMirage => band == 'mirage';
}

/// One tick of a live hunt, as the server is willing to describe it.
///
/// Note what is absent, again: no bearing, no coordinate, no id for the person
/// being chased. [state] is what they are doing, which the hunter is allowed to
/// know only because they were told they were being hunted before they did it.
class HuntTick {
  const HuntTick({
    required this.band,
    required this.state,
    required this.seconds,
  });

  factory HuntTick.fromRow(Map<String, dynamic> r) => HuntTick(
        band: (r['band'] ?? 'lost') as String,
        state: (r['state'] ?? 'none') as String,
        seconds: (r['seconds'] ?? 0) as int,
      );

  static const none = HuntTick(band: 'lost', state: 'none', seconds: 0);

  final String band, state;

  /// Seconds left on whatever clock is currently running: the freeze if they
  /// are standing still, the hunt itself otherwise.
  final int seconds;

  /// The floor, reached. The server has deleted the hunt and will not answer
  /// again — there is nothing further to ask it.
  bool get burst => state == 'burst';

  bool get frozen => state == 'frozen';

  /// Every way a hunt can stop being a hunt.
  bool get over =>
      burst ||
      state == 'none' ||
      state == 'gone' ||
      state == 'dissolved';
}

/// What someone being hunted is allowed to know: that it is happening, how
/// many, and how close the nearest one is. There is no field here for who,
/// because there is no column for it in the table this comes from.
class HuntedState {
  const HuntedState({
    required this.hunters,
    required this.nearest,
    required this.frozen,
  });

  factory HuntedState.fromRow(Map<String, dynamic> r) => HuntedState(
        hunters: (r['hunters'] ?? 0) as int,
        nearest: (r['nearest'] ?? 'none') as String,
        frozen: (r['frozen'] ?? false) as bool,
      );

  static const calm = HuntedState(hunters: 0, nearest: 'none', frozen: false);

  final int hunters;
  final String nearest;
  final bool frozen;

  bool get hunted => hunters > 0;
}

/// A spore someone left behind, once they have walked far enough away from it
/// that it no longer points at a person.
class RemoteSpore {
  const RemoteSpore({required this.id, required this.band, required this.created});

  factory RemoteSpore.fromRow(Map<String, dynamic> r) => RemoteSpore(
        id: r['id'] as String,
        band: (r['band'] ?? 'cold') as String,
        created: DateTime.parse(r['created'] as String),
      );

  final String id, band;
  final DateTime created;
}

class CampusEmailRejected implements Exception {
  const CampusEmailRejected();
  @override
  String toString() => 'That address is not a campus one.';
}


/// Everything the app is allowed to ask the database.
///
/// Note what is absent: there is no `getWhisperLocation`, no `getUsers`, no
/// way to read a beacon. Those calls do not exist here because the policies
/// upstream would refuse them anyway.
class SwarmApi {
  SwarmApi._(this._db);

  final SupabaseClient _db;
  static SwarmApi? _instance;
  static SwarmApi get instance => _instance!;
  static bool get ready => _instance != null;

  static Future<SwarmApi> connect() async {
    await Supabase.initialize(
      url: Config.url,
      publishableKey: Config.key,
      // OAuth 2.0 uses PKCE. The SDK detects the callback URL,
      // exchanges the authorization code, persists the session, and cleans
      // the browser URL on web.
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: true,
        authFlowType: AuthFlowType.pkce,
      ),
    );
    final api = SwarmApi._(Supabase.instance.client);
    _instance = api;
    api._guardTheDoor();
    return api;
  }

  /// One place where "you are in" becomes true, whichever auth method was used.
  ///
  /// OAuth can authenticate any valid mailbox, so the domain check is applied
  /// again to the resulting session. If the address is not a campus one, the
  /// session is thrown away before any screen behind the gate is built.
  void _guardTheDoor() {
    _db.auth.onAuthStateChange.listen((state) async {
      if (state.event != AuthChangeEvent.signedIn) return;
      final u = state.session?.user;
      if (u == null) return;

      final email = u.email;
      if (email != null && !isCampusEmail(email)) {
        await _db.auth.signOut();
        _refused.add(email);
        return;
      }
      // A convenience row, not a gate — never trade a good session for it.
      try {
        await _db.from('profiles').upsert({'id': u.id});
      } catch (_) {}
    });
  }

  /// Addresses turned away at the door after the fact. The gate listens so a
  /// social login that lands on a personal mailbox says why, instead of
  /// bouncing back to the sign-in screen with no explanation.
  final _refused = StreamController<String>.broadcast();
  Stream<String> get refusals => _refused.stream;

  User? get user => _db.auth.currentUser;
  bool get signedIn => user != null;

  /// Campus domains that count. The gate is the domain, not a document
  /// upload or a student-ID photo — nobody has to hand us anything sensitive
  /// to prove they belong here.
  static const campusDomains = <String>[
    '.edu', '.ac.in', '.edu.in', '.ac.uk', '.edu.au', '.ac.nz', '.edu.pk',
  ];

  static bool isCampusEmail(String email) {
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$').hasMatch(e)) return false;
    if (Config.pilotOpenSignup) return true;
    return campusDomains.any(e.endsWith);
  }

  /// Where OAuth and password-recovery callbacks should return.
  ///
  /// Add the deployed web origin and `closer://auth-callback` under:
  /// Authentication -> URL Configuration -> Redirect URLs.
  static String? get _redirectTo {
    if (kIsWeb) return Uri.base.origin;
    return 'closer://auth-callback';
  }

  /// Sign in with any OAuth 2.0 provider enabled in Supabase.
  Future<void> signInWith(OAuthProvider provider) =>
      _db.auth.signInWithOAuth(provider, redirectTo: _redirectTo);

  /// Create an account with email and password.
  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    if (!isCampusEmail(e)) {
      throw const CampusEmailRejected();
    }

    return _db.auth.signUp(
      email: e,
      password: password,
      emailRedirectTo: _redirectTo,
    );
  }

  /// Sign in to an existing account with email and password.
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    if (!isCampusEmail(e)) {
      throw const CampusEmailRejected();
    }

    return _db.auth.signInWithPassword(
      email: e,
      password: password,
    );
  }

  /// Send the password-recovery email for an existing account.
  ///
  /// This is only for password recovery. Passwordless/magic-link login is not
  /// exposed by this API anymore.
  Future<void> sendPasswordReset(String email) async {
    final e = email.trim().toLowerCase();
    if (!isCampusEmail(e)) {
      throw const CampusEmailRejected();
    }

    await _db.auth.resetPasswordForEmail(
      e,
      redirectTo: _redirectTo,
    );
  }

  /// Set a new password after the recovery callback has created a session.
  Future<UserResponse> updatePassword(String newPassword) =>
      _db.auth.updateUser(
        UserAttributes(password: newPassword),
      );

  /// Close a realtime channel. A chat sheet that opens and closes twenty
  /// times a night must not leave twenty sockets behind it.
  Future<void> drop(RealtimeChannel channel) => _db.removeChannel(channel);

  Future<void> signOut() => _db.auth.signOut();

  /// Give a persisted or redirected OAuth session a chance to appear before
  /// anyone decides to show the sign-in screen.
  Future<void> restoreSession() async {
    if (signedIn) return;
    if (_urlCarriesAuth) {
      try {
        await authChanges
            .firstWhere((s) => s.event == AuthChangeEvent.signedIn)
            .timeout(const Duration(seconds: 10));
        return;
      } catch (_) {
        // Invalid or expired OAuth/recovery callback. Show the sign-in screen.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  /// OAuth PKCE returns `?code=...`; recovery callbacks can also carry auth
  /// parameters. Let Supabase consume them before rebuilding the auth gate.
  static bool get _urlCarriesAuth {
    if (!kIsWeb) return false;
    final u = Uri.base;
    final both = '${u.fragment}&${u.query}';
    return both.contains('code=') ||
        both.contains('access_token=') ||
        both.contains('refresh_token=') ||
        both.contains('error=');
  }

  Stream<AuthState> get authChanges => _db.auth.onAuthStateChange;

  /// Push your position. It goes in and is never readable again — not by you,
  /// not by anyone, only by the RPCs that turn it into a band.
  Future<void> beacon(double lat, double lon) =>
      _db.rpc('beacon_set', params: {'lat': lat, 'lon': lon});

  /// A sonar sweep. Returns bodies and bands for whispers within [radius]
  /// metres, and nothing else.
  ///
  /// [minBoosts] is what zoom means. Pulling back does not mean "send me
  /// everything further away" — that is how a map becomes soup and a payload
  /// becomes a leak. It means "only the loud ones", the way a country survives
  /// zooming out and a single house does not. The floor is applied in
  /// Postgres, so the quiet whispers are never sent rather than being sent and
  /// then dropped.
  Future<List<RemoteWhisper>> sweep({
    double radius = 132,
    int minBoosts = 0,
  }) async {
    final rows = await _db.rpc('sweep', params: {
      'radius_m': radius,
      'min_boosts': minBoosts,
    }) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(RemoteWhisper.fromRow)
        .toList();
  }

  /// The boost floor for a given map zoom, and the radius that goes with it.
  ///
  /// One place owns this curve so the map, the sweep and the painter cannot
  /// disagree about what is supposed to be visible. Zoom 18 is a courtyard;
  /// zoom 13 is the whole city and only the loudest thing on campus survives
  /// it.
  static ({double radius, int minBoosts}) lens(double zoom) {
    // The bottom rung shows everything within earshot, and it is the rung the
    // app must OPEN on — a whisper is posted with zero boosts, so opening on
    // any tier above this one makes a new whisper invisible to everyone,
    // including the people who would have boosted it. See `Ground.zoom`.
    if (zoom >= 18) return (radius: 140, minBoosts: 0);
    if (zoom >= 16.5) return (radius: 320, minBoosts: 1);
    if (zoom >= 15) return (radius: 700, minBoosts: 3);
    if (zoom >= 13.5) return (radius: 1600, minBoosts: 8);
    return (radius: 4000, minBoosts: 20);
  }

  // ------------------------------------------------------------- rooms
  // A whisper is shouted and lost. A room is where two people who found each
  // other can actually talk — under every rule the whispers live by.

  /// Open a room at your own beacon. The client sends no coordinate; the
  /// server reads the position you already pushed. One at a time, enforced by
  /// a trigger rather than by this method.
  Future<String> openRoom(String title,
          {int radius = 120, int minutes = 60}) async =>
      await _db.rpc('room_open', params: {
        'title_in': title,
        'radius_in': radius,
        'minutes_in': minutes,
      }) as String;

  /// Rooms you can see from where you stand — bands and headcounts only.
  Future<List<Room>> roomsNear({double within = 300}) async {
    final rows = await _db.rpc('rooms_near', params: {'within_m': within})
        as List;
    return rows.cast<Map<String, dynamic>>().map(Room.fromRow).toList();
  }

  /// Walk in. Returns the handle you will wear inside — HERON-2 — which is
  /// yours for the life of the room and means nothing outside it. Throws
  /// 'out of range' if you are not actually standing near enough; the door is
  /// physical, and the check is the server's, not the button's.
  Future<String> joinRoom(String id) async =>
      await _db.rpc('room_join', params: {'target': id}) as String;

  Future<void> leaveRoom(String id) =>
      _db.rpc('room_leave', params: {'target': id});

  Future<String> say(String roomId, String body) async =>
      await _db.rpc('room_say', params: {
        'target': roomId,
        'body_in': body,
      }) as String;

  Future<List<ChatLine>> history(String roomId, {int limit = 60}) async {
    final rows = await _db.rpc('room_history', params: {
      'target': roomId,
      'limit_in': limit,
    }) as List;
    final lines =
        rows.cast<Map<String, dynamic>>().map(ChatLine.fromRow).toList();
    return lines.reversed.toList(); // newest last, the way a chat reads
  }

  /// Silence whoever said a line, without ever learning who they are.
  Future<bool> blockSpeaker(String messageId) async =>
      await _db.rpc('block_speaker', params: {'target': messageId}) as bool;

  /// Lines arriving in one room, live. RLS on `messages` is what makes this
  /// safe to subscribe to: a non-member's socket receives nothing, because the
  /// policy refuses the row rather than the client hiding it.
  RealtimeChannel liveRoom(String roomId, void Function(ChatLine) onLine) => _db
      .channel('room:$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room',
          value: roomId,
        ),
        callback: (payload) =>
            onLine(ChatLine.fromLiveRow(payload.newRecord, user?.id)),
      )
      .subscribe();

  /// Post at your own beacon. The client never sends a coordinate — the server
  /// reads the one you already pushed.
  Future<String> post(String body, {String bloom = 'nightly'}) async =>
      await _db.rpc('post_whisper', params: {
        'body_in': body,
        'bloom_in': bloom,
      }) as String;

  /// Once per whisper, ever — enforced by a primary key, not by the UI.
  Future<bool> boost(String whisperId) async {
    final r = await _db.rpc('boost_whisper', params: {'target': whisperId});
    return (r as int) > 0;
  }

  /// How far, never where. Returns 'mirage' under ten metres and stops there.
  Future<String> band(String whisperId) async =>
      await _db.rpc('whisper_band', params: {'target': whisperId}) as String;

  // ------------------------------------------------------------- hunts
  // Until now the hunt was a puppet: the engine rolled a die to decide whether
  // a target froze or ran. These are the calls that make the other half of it
  // a person, who is told, and who can refuse.

  /// Begin tracking whoever wrote a whisper. Returns the opening band, or
  /// 'mirage' if you were already inside the floor — in which case no hunt was
  /// started and there is nothing to ping.
  Future<String> huntStart(String whisperId) async =>
      await _db.rpc('hunt_start', params: {'target': whisperId}) as String;

  /// One tick of the ring. The only call in this class that is expected to be
  /// made on a timer, because it is the only one whose answer changes when
  /// nobody has touched the phone.
  Future<HuntTick> huntPing() async {
    final rows = await _db.rpc('hunt_ping') as List;
    if (rows.isEmpty) return HuntTick.none;
    return HuntTick.fromRow(rows.first as Map<String, dynamic>);
  }

  Future<void> huntDrop() => _db.rpc('hunt_drop');

  /// The prey half. Safe to call on a timer for the same reason.
  Future<HuntedState> hunted() async {
    final rows = await _db.rpc('hunted_state') as List;
    if (rows.isEmpty) return HuntedState.calm;
    return HuntedState.fromRow(rows.first as Map<String, dynamic>);
  }

  /// The freeze right. Standing still dissolves your signal — to everyone, not
  /// only to whoever is already chasing you. Nothing anywhere counters this.
  Future<bool> freezeSignal(bool on) async =>
      await _db.rpc('freeze_signal', params: {'on_in': on}) as bool;

  /// Being told, live. This is the channel that makes rule three true rather
  /// than merely polled: `hunt_alerts` has no hunter column, which is what
  /// makes a socket on it safe to open at all.
  RealtimeChannel liveHunted(void Function(String band) onAlert) => _db
      .channel('swarm:hunted')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'hunt_alerts',
        callback: (payload) =>
            onAlert((payload.newRecord['band'] ?? 'cold') as String),
      )
      .subscribe();

  // ------------------------------------------------------------- spores
  // The one thing in the app that points at a place rather than a person —
  // which it is only allowed to do because by the time anyone can see it, its
  // author is somewhere else.

  Future<String> sporeDrop() async => await _db.rpc('spore_drop') as String;

  Future<List<RemoteSpore>> sporesNear({double within = 300}) async {
    final rows = await _db.rpc('spores_near', params: {'within_m': within})
        as List;
    return rows.cast<Map<String, dynamic>>().map(RemoteSpore.fromRow).toList();
  }

  // ------------------------------------------------------------- safety
  // Apple Guideline 1.2 requires a filter, a report path, and blocking for any
  // app with anonymous chat. All three are enforced in Postgres; these are
  // only the doorways to them.

  /// A courtesy check so someone gets an instant answer instead of a silent
  /// failure. The server screens again on insert — this is never the control.
  static final _filter = [
    RegExp(r'kill\s*your\s*self', caseSensitive: false),
    RegExp(r'\bkys\b', caseSensitive: false),
    RegExp(r'\bgo die\b', caseSensitive: false),
    RegExp(r'rape', caseSensitive: false),
    RegExp(r'\bn[i1l]gg', caseSensitive: false),
    RegExp(r'\bf[a4]gg', caseSensitive: false),
  ];
  static bool wouldBeBlocked(String body) => _filter.any((r) => r.hasMatch(body));

  /// Report a post. Anonymous in both directions: the author is never told who
  /// reported them, and the reporter never learns who they reported. The server
  /// snapshots the text first, because the post itself dies within the minute.
  Future<String> report(
    String targetId, {
    required String reason,
    String kind = 'post',
    String? detail,
  }) async =>
      await _db.rpc('report', params: {
        'kind_in': kind,
        'target_in': targetId,
        'reason_in': reason,
        'detail_in': detail,
      }) as String;

  /// Block whoever wrote a post — without ever learning who that is. The id is
  /// resolved inside a security-definer function and never returned; even the
  /// blocks table is unreadable from a client, because two rows in it would be
  /// enough to tell whether two anonymous posts came from one person.
  Future<bool> blockAuthorOf(String postId) async =>
      await _db.rpc('block_author', params: {'target': postId}) as bool;

  Future<int> blockedCount() async => await _db.rpc('my_blocks') as int;

  Future<List<Map<String, dynamic>>> myReports() async =>
      (await _db.rpc('my_reports') as List).cast<Map<String, dynamic>>();

  Future<int> unblockAll() async => await _db.rpc('unblock_all') as int;

  Future<List<Map<String, dynamic>>> blooms() async =>
      (await _db.from('blooms').select().order('starts'))
          .cast<Map<String, dynamic>>();

  /// New whispers landing on campus, live. Carries no geography — the payload
  /// is filtered by the same policies as everything else.
  RealtimeChannel liveWhispers(void Function() onChange) => _db
      .channel('swarm:whispers')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'whispers',
        callback: (_) => onChange(),
      )
      .subscribe();
}
