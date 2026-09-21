import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/peer_message.dart';
import 'peer_server.dart';
import 'peer_client.dart';

enum SessionRole { none, host, member }

/// Holds the complete state of the current collaboration session.
/// Used as a ChangeNotifier so UI can rebuild reactively.
class PeerSession extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final PeerSession instance = PeerSession._();
  PeerSession._();

  // ── State ────────────────────────────────────────────────────────────────
  SessionRole role = SessionRole.none;
  String myName = '';
  String hostAddress = ''; // "ip:port" used by members
  String serverAddress = ''; // shown to host in QR

  final PeerServer _server = PeerServer();
  final PeerClient _client = PeerClient();

  StreamSubscription<PeerMessage>? _sub;

  /// Map of peer name → their last known position
  final Map<String, LatLng> peerLocations = {};
  final Map<String, double> peerHeadings = {};
  final Map<String, int> peerLastSeen = {};

  /// All chat messages in order
  final List<PeerMessage> chatMessages = [];
  int unreadChat = 0;

  /// All received markers
  final List<PeerMessage> sharedMarkers = [];

  /// All alert messages
  final List<PeerMessage> alerts = [];

  /// Connected member names (from roster, host only)
  List<String> members = [];

  bool get isActive => role != SessionRole.none;

  // ── Host ─────────────────────────────────────────────────────────────────

  Future<String> startAsHost(String name) async {
    myName = name;
    role = SessionRole.host;
    serverAddress = await _server.start();
    _sub = _server.messages.listen(_handleMessage);
    notifyListeners();
    return serverAddress;
  }

  void broadcastFromHost(PeerMessage msg) {
    if (role == SessionRole.host) _server.broadcast(msg);
  }

  // ── Member ───────────────────────────────────────────────────────────────

  Future<void> joinAsClient(String name, String address) async {
    myName = name;
    hostAddress = address;
    role = SessionRole.member;
    await _client.connect(address, name);
    _sub = _client.messages.listen(_handleMessage);
    notifyListeners();
  }

  void sendFromClient(PeerMessage msg) {
    if (role == SessionRole.member) _client.send(msg);
  }

  // ── Unified send (works for both host and member) ─────────────────────────

  void sendMessage(PeerMessage msg) {
    if (role == SessionRole.host) {
      _server.broadcast(msg);
    } else if (role == SessionRole.member) {
      _client.send(msg);
    }
  }

  /// Add a chat message from yourself to the local list and notify listeners.
  void addOwnChat(String text) {
    final msg = PeerMessage.chat(from: myName, text: text);
    chatMessages.add(msg);
    notifyListeners();
  }

  // ── Message handler ──────────────────────────────────────────────────────

  void _handleMessage(PeerMessage msg) {
    switch (msg.type) {
      case PeerMessageType.location:
        if (msg.lat != null && msg.lng != null) {
          peerLocations[msg.from] = LatLng(msg.lat!, msg.lng!);
          peerHeadings[msg.from] = msg.heading ?? 0;
          peerLastSeen[msg.from] = msg.ts;
        }
      case PeerMessageType.chat:
        chatMessages.add(msg);
        unreadChat++;
      case PeerMessageType.marker:
        sharedMarkers.add(msg);
      case PeerMessageType.alert:
        alerts.add(msg);
        chatMessages.add(msg); // also show in chat
        unreadChat++;
      case PeerMessageType.roster:
        members = msg.members ?? [];
      case PeerMessageType.bye:
        peerLocations.remove(msg.from);
        peerHeadings.remove(msg.from);
        peerLastSeen.remove(msg.from);
      case PeerMessageType.ping:
        break;
    }
    notifyListeners();
  }

  // ── Location broadcast (called periodically from map screen) ─────────────

  void broadcastMyLocation(double lat, double lng, double heading) {
    if (!isActive) return;
    sendMessage(
      PeerMessage.location(from: myName, lat: lat, lng: lng, heading: heading),
    );
  }

  void clearUnread() {
    unreadChat = 0;
    notifyListeners();
  }

  // ── Stop ─────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    sendMessage(PeerMessage.bye(from: myName));
    await _sub?.cancel();
    await _server.stop();
    await _client.disconnect();
    role = SessionRole.none;
    myName = '';
    peerLocations.clear();
    peerHeadings.clear();
    peerLastSeen.clear();
    chatMessages.clear();
    sharedMarkers.clear();
    alerts.clear();
    members = [];
    unreadChat = 0;
    notifyListeners();
  }
}
