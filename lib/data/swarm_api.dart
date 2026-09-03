import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

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
    await Supabase.initialize(url: Config.url, publishableKey: Config.key);
    final api = SwarmApi._(Supabase.instance.client);
    _instance = api;
    return api;
  }

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

  /// Send a six-digit code. Deliberately not a clickable link: deep-linking a
  /// magic link into iOS, Android and web all at once is three separate
  /// configuration problems, and a typed code is none of them.
  Future<void> sendCode(String email) async {
    final e = email.trim().toLowerCase();
    if (!isCampusEmail(e)) {
      throw const CampusEmailRejected();
    }
    await _db.auth.signInWithOtp(email: e, shouldCreateUser: true);
  }

  /// Accepts whichever thing the email actually contained.
  ///
  /// Supabase's default template ships a *link*, not a code, and changing that
  /// is a dashboard edit nobody should need to make before their first login.
  /// So paste either: a numeric code, or the whole link — we pull the token
  /// hash straight out of it.
  Future<void> verifyCode(String email, String input) async {
    final raw = input.trim();
    final hash = _tokenHashIn(raw);

    if (hash != null) {
      await _db.auth.verifyOTP(tokenHash: hash, type: OtpType.magiclink);
    } else {
      await _db.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: raw.replaceAll(RegExp(r'[^0-9]'), ''),
        type: OtpType.email,
      );
    }
    await _db.from('profiles').upsert({'id': user!.id});
  }

  /// Magic links carry `?token=<hash>&type=magiclink`. Some clients rewrite
  /// them through a tracker, so we look for the parameter rather than trusting
  /// the host.
  static String? _tokenHashIn(String s) {
    if (!s.contains('token')) return null;
    final m = RegExp(r'[?&](?:token|token_hash)=([A-Za-z0-9_-]+)').firstMatch(s);
    return m?.group(1);
  }

  Future<void> signOut() => _db.auth.signOut();

  /// Give the stored session a moment to come back off disk before anyone
  /// decides whether to show the door.
  Future<void> restoreSession() async {
    if (signedIn) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Stream<AuthState> get authChanges => _db.auth.onAuthStateChange;

  /// Push your position. It goes in and is never readable again — not by you,
  /// not by anyone, only by the RPCs that turn it into a band.
  Future<void> beacon(double lat, double lon) =>
      _db.rpc('beacon_set', params: {'lat': lat, 'lon': lon});

  /// A sonar sweep. Returns bodies and bands for whispers within [radius]
  /// metres, and nothing else.
  Future<List<RemoteWhisper>> sweep({double radius = 132}) async {
    final rows = await _db.rpc('sweep', params: {'radius_m': radius}) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(RemoteWhisper.fromRow)
        .toList();
  }

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
