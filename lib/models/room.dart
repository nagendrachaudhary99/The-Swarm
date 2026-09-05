/// A room as the server is willing to describe it.
///
/// Note what is missing, again: no coordinate, no host, no member list. A room
/// is a title, a distance BAND, and a headcount. The client could not draw a
/// room in the wrong place if it wanted to, because it was never told where
/// one is — [band] is the only spatial fact it holds.
class Room {
  const Room({
    required this.id,
    required this.title,
    required this.band,
    required this.members,
    required this.diesAt,
    required this.joined,
    required this.inRange,
  });

  factory Room.fromRow(Map<String, dynamic> r) => Room(
        id: r['id'] as String,
        title: r['title'] as String,
        band: (r['band'] ?? 'cold') as String,
        members: (r['members'] ?? 0) as int,
        diesAt: DateTime.parse(r['dies_at'] as String),
        joined: (r['joined'] ?? false) as bool,
        inRange: (r['in_range'] ?? false) as bool,
      );

  final String id, title, band;
  final int members;
  final DateTime diesAt;

  /// You are already inside.
  final bool joined;

  /// You are standing close enough to get in. The server checks this again on
  /// join — this is only so the button can say so before you press it.
  final bool inRange;

  Duration get remaining => diesAt.difference(DateTime.now());
  bool get dead => remaining.isNegative;

  /// Roughly how far, for sorting and for the ring radius. The band is the
  /// truth; this is the band read back as a number so the painter has one.
  double get metres => switch (band) {
        'mirage' => 8,
        'critical' => 25,
        'hot' => 60,
        'warm' => 130,
        _ => 220,
      };
}

/// One line of chat. Attributed to a handle that means nothing outside its own
/// room, and dies when the room does.
class ChatLine {
  const ChatLine({
    required this.id,
    required this.handle,
    required this.body,
    required this.said,
    required this.mine,
  });

  factory ChatLine.fromRow(Map<String, dynamic> r) => ChatLine(
        id: r['id'] as String,
        handle: (r['handle'] ?? '···') as String,
        body: r['body'] as String,
        said: DateTime.parse(r['said'] as String),
        mine: (r['mine'] ?? false) as bool,
      );

  /// Realtime hands over the raw row, which has an `author` rather than the
  /// `mine` the RPC computes — so the caller says who it is.
  factory ChatLine.fromLiveRow(Map<String, dynamic> r, String? me) => ChatLine(
        id: r['id'] as String,
        handle: (r['handle'] ?? '···') as String,
        body: r['body'] as String,
        said: DateTime.parse(r['said'] as String),
        mine: me != null && r['author'] == me,
      );

  final String id, handle, body;
  final DateTime said;
  final bool mine;
}
