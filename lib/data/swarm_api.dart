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

class CampusEmailRejected implements Exception {
  const CampusEmailRejected();
  @override
  String toString() => 'That address is not a campus one.';
}

/// A token pulled out of a pasted magic link, with the kind Supabase stamped
/// on it. The kind matters: verifying a `signup` hash as a `magiclink` is
/// rejected exactly the way a wrong code is.
class _LinkToken {
  const _LinkToken(this.hash, this.type);
  final String hash;
  final OtpType type;
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
      // A clicked link comes back with the session in the URL. Let the SDK
      // pick it up and clean the address bar, so arriving from an email lands
      // in exactly the same state as typing a code.
      //
      // Implicit, not the PKCE default, and this is the whole reason a clicked
      // link used to loop back to the gate. PKCE keeps a code verifier in the
      // storage of the browser that ASKED for the link, and the mailed link is
      // then worth nothing anywhere else — but a mail app opens links in its
      // own in-app browser, so "anywhere else" is the normal case, not the
      // edge one. The exchange failed with no session, the root rebuilt, and
      // the door reappeared. Implicit puts the tokens in the URL itself, so
      // whichever browser opens the link is the one that gets signed in.
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: true,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    final api = SwarmApi._(Supabase.instance.client);
    _instance = api;
    api._guardTheDoor();
    return api;
  }

  /// One place where "you are in" becomes true, whichever door was used.
  ///
  /// A social login never passes through [sendCode], so the domain check would
  /// simply not happen — Google will happily vouch for any address alive. We
  /// therefore re-apply the same rule to the session itself: if the address is
  /// not a campus one the session is thrown away immediately, before any
  /// screen behind the gate is built.
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

  /// A pilot cohort signs in anonymously so two phones can be tested in a
  /// corridor. Real launch swaps this for an `.edu` magic link — same session,
  /// same RLS, one line different.
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

  /// Where Supabase should send someone after it verifies a link.
  ///
  /// Without this it uses the project's Site URL, which ships as
  /// `http://localhost:3000` and is almost never where the app is actually
  /// running — you click the link, get signed in, and land on a dead port with
  /// the token already spent. Supabase always permits `localhost`, so on web we
  /// simply name the origin we are being served from and the problem is gone.
  ///
  /// A deployed origin is NOT permitted by default: it has to be added under
  /// Authentication → URL Configuration → Redirect URLs, or Supabase silently
  /// falls back to the Site URL again.
  static String? get _redirectTo {
    if (kIsWeb) return Uri.base.origin;
    return 'closer://auth-callback';
  }

  /// Send a one-time code. Deliberately not a clickable link: deep-linking a
  /// magic link into iOS, Android and web all at once is three separate
  /// configuration problems, and a typed code is none of them. The length is
  /// the project's `mailer_otp_length` (8 today), so nothing here counts
  /// digits — `verifyCode` strips everything that is not one and sends the
  /// rest.
  Future<void> sendCode(String email) async {
    final e = email.trim().toLowerCase();
    if (!isCampusEmail(e)) {
      throw const CampusEmailRejected();
    }
    await _db.auth.signInWithOtp(
      email: e,
      shouldCreateUser: true,
      emailRedirectTo: _redirectTo,
    );
  }

  /// The door that needs no mail at all.
  ///
  /// Nothing is sent, nothing is typed, and none of it touches the project's
  /// mail settings — which is the entire point: a free project cannot put a
  /// code in an email, so the sturdiest login here is the one that never asks
  /// for one. On web this leaves the page and comes back with the session in
  /// the URL, where `detectSessionInUri` picks it up and the root rebuilds
  /// itself signed in.
  Future<void> signInWith(OAuthProvider provider) =>
      _db.auth.signInWithOAuth(provider, redirectTo: _redirectTo);

  /// Accepts whichever thing the email actually contained.
  ///
  /// If the templates carry `{{ .Token }}` this is a six-digit code and the
  /// second branch runs. If they were left as Supabase ships them it is a
  /// *link*, so we pull the token hash out of it — along with its `type`,
  /// which is `signup` on a first login and `magiclink` afterwards. Assuming
  /// one of those is why a brand-new address used to be refused.
  Future<void> verifyCode(String email, String input) async {
    final raw = input.trim();
    final e = email.trim().toLowerCase();
    final link = _tokenIn(raw);

    if (link != null) {
      try {
        await _db.auth.verifyOTP(tokenHash: link.hash, type: link.type);
      } on AuthException {
        // The link said one thing and the server meant the other — which
        // happens when a template was hand-edited. One retry, then it really
        // is a bad token.
        final other =
            link.type == OtpType.signup ? OtpType.magiclink : OtpType.signup;
        await _db.auth.verifyOTP(tokenHash: link.hash, type: other);
      }
    } else {
      await _db.auth.verifyOTP(
        email: e,
        token: raw.replaceAll(RegExp(r'[^0-9]'), ''),
        type: OtpType.email,
      );
    }

    // The profile row is not written here. `_guardTheDoor` does it for every
    // door at once, so a code and a social login cannot drift apart.
  }

  /// Magic links carry `?token=<hash>&type=<kind>`. Some clients rewrite them
  /// through a tracker, so we look for the parameters rather than trusting the
  /// host. A bare hash pasted on its own counts too: nothing else that long is
  /// free of digits.
  static _LinkToken? _tokenIn(String s) {
    final m = RegExp(r'[?&](?:token_hash|token)=([A-Za-z0-9_-]+)').firstMatch(s);
    if (m != null) {
      final kind = RegExp(r'[?&]type=([a-z_]+)').firstMatch(s)?.group(1);
      return _LinkToken(m.group(1)!, _otpType(kind));
    }
    if (RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(s) &&
        !RegExp(r'^[0-9]+$').hasMatch(s)) {
      // A hash with no URL around it. We cannot know the kind, and signup is
      // the one that bites first-time users, so start there.
      return _LinkToken(s, OtpType.signup);
    }
    return null;
  }

  static OtpType _otpType(String? kind) => switch (kind) {
        'signup' => OtpType.signup,
        'recovery' => OtpType.recovery,
        'invite' => OtpType.invite,
        'email_change' => OtpType.emailChange,
        'email' => OtpType.email,
        _ => OtpType.magiclink,
      };

  /// Close a realtime channel. A chat sheet that opens and closes twenty
  /// times a night must not leave twenty sockets behind it.
  Future<void> drop(RealtimeChannel channel) => _db.removeChannel(channel);

  Future<void> signOut() => _db.auth.signOut();

  /// Give a session a chance to appear before anyone decides to show the door.
  ///
  /// Two different waits hide in here. A session stored on disk comes back in
  /// a few frames. A session arriving *in the URL* costs a network round trip
  /// to Supabase — and 350ms of guessing is how a perfectly good link ends up
  /// showing the sign-in screen anyway. So when the address bar is carrying
  /// auth parameters we wait for the sign-in itself, and only give up after
  /// long enough that giving up means it really failed.
  Future<void> restoreSession() async {
    if (signedIn) return;
    if (_urlCarriesAuth) {
      try {
        await authChanges
            .firstWhere((s) => s.event == AuthChangeEvent.signedIn)
            .timeout(const Duration(seconds: 10));
        return;
      } catch (_) {
        // Expired, already spent, or refused. The door is the honest answer.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  /// Is this page load the tail end of a clicked link? Implicit flow returns
  /// the tokens in the fragment; an error comes back the same way.
  static bool get _urlCarriesAuth {
    if (!kIsWeb) return false;
    final u = Uri.base;
    final both = '${u.fragment}&${u.query}';
    return both.contains('access_token=') ||
        both.contains('error=') ||
        both.contains('code=');
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
