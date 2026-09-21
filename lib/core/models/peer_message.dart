import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Types of messages exchanged between peers.
enum PeerMessageType { location, chat, marker, alert, ping, roster, bye }

/// A single message exchanged over the WebSocket session.
class PeerMessage {
  final String msgId;
  final PeerMessageType type;
  final String from;
  final int ts;
  final double? lat;
  final double? lng;
  final double? heading;
  final String? text;
  final String? level;
  final String? label;
  final List<String>? members;

  const PeerMessage({
    required this.msgId,
    required this.type,
    required this.from,
    required this.ts,
    this.lat,
    this.lng,
    this.heading,
    this.text,
    this.level,
    this.label,
    this.members,
  });

  factory PeerMessage.location({required String from, required double lat, required double lng, double heading = 0}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.location, from: from, ts: DateTime.now().millisecondsSinceEpoch, lat: lat, lng: lng, heading: heading);

  factory PeerMessage.chat({required String from, required String text}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.chat, from: from, ts: DateTime.now().millisecondsSinceEpoch, text: text);

  factory PeerMessage.marker({required String from, required double lat, required double lng, required String label}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.marker, from: from, ts: DateTime.now().millisecondsSinceEpoch, lat: lat, lng: lng, label: label);

  factory PeerMessage.alert({required String from, required String text, required String level, double? lat, double? lng}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.alert, from: from, ts: DateTime.now().millisecondsSinceEpoch, text: text, level: level, lat: lat, lng: lng);

  factory PeerMessage.ping({required String from}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.ping, from: from, ts: DateTime.now().millisecondsSinceEpoch);

  factory PeerMessage.bye({required String from}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.bye, from: from, ts: DateTime.now().millisecondsSinceEpoch);

  factory PeerMessage.roster({required String from, required List<String> members}) =>
      PeerMessage(msgId: const Uuid().v4(), type: PeerMessageType.roster, from: from, ts: DateTime.now().millisecondsSinceEpoch, members: members);

  Map<String, dynamic> toJson() => {
        'msgId': msgId, 'type': type.name, 'from': from, 'ts': ts,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (heading != null) 'heading': heading,
        if (text != null) 'text': text,
        if (level != null) 'level': level,
        if (label != null) 'label': label,
        if (members != null) 'members': members,
      };

  String toJsonString() => jsonEncode(toJson());

  factory PeerMessage.fromJson(Map<String, dynamic> j) => PeerMessage(
        msgId: j['msgId'] as String? ?? const Uuid().v4(),
        type: PeerMessageType.values.firstWhere((e) => e.name == j['type'], orElse: () => PeerMessageType.ping),
        from: j['from'] as String? ?? 'Unknown',
        ts: j['ts'] as int? ?? 0,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
        text: j['text'] as String?,
        level: j['level'] as String?,
        label: j['label'] as String?,
        members: (j['members'] as List?)?.cast<String>(),
      );

  factory PeerMessage.fromJsonString(String s) =>
      PeerMessage.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
