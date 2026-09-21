import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/peer_message.dart';

/// Holds the state for the Mesh Network session.
/// In a mesh, this device acts as BOTH a server and a client.
class MeshSession extends ChangeNotifier {
  static final MeshSession instance = MeshSession._();
  MeshSession._();

  bool isActive = false;
  String myName = '';
  String localServerAddress = ''; // IP:Port this device is listening on

  HttpServer? _httpServer;
  
  // All active connections (both incoming and outgoing)
  final List<WebSocketChannel> _channels = [];
  
  // To prevent infinite loops in the mesh
  final List<String> _seenMsgIds = [];
  static const int _maxSeenIds = 1000;

  // ── State ────────────────────────────────────────────────────────────────
  final Map<String, LatLng> peerLocations = {};
  final Map<String, double> peerHeadings = {};
  final Map<String, int> peerLastSeen = {};
  
  final List<PeerMessage> chatMessages = [];
  int unreadChat = 0;

  // ── Start Node (Server) ──────────────────────────────────────────────────
  Future<String> startNode(String name) async {
    myName = name;
    isActive = true;
    
    final handler = webSocketHandler((WebSocketChannel ws, _) {
      _addChannel(ws);
    });

    _httpServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8766); // using 8766 for mesh
    final ip = await _getLocalIp();
    localServerAddress = '$ip:8766';
    
    notifyListeners();
    return localServerAddress;
  }

  // ── Connect to Node (Client) ─────────────────────────────────────────────
  Future<void> connectToNode(String address) async {
    if (!isActive) throw Exception("Start your node first");
    
    final uri = Uri.parse('ws://$address');
    final ws = WebSocketChannel.connect(uri);
    await ws.ready;
    _addChannel(ws);
    
    // Announce ourselves to the new connection (and it will flood through the mesh)
    broadcast(PeerMessage.ping(from: myName));
  }

  // ── Channel Management ───────────────────────────────────────────────────
  void _addChannel(WebSocketChannel ws) {
    _channels.add(ws);
    notifyListeners(); // Update connected count

    ws.stream.listen(
      (data) {
        try {
          final jsonStr = data as String;
          final msg = PeerMessage.fromJsonString(jsonStr);
          
          // Deduplication
          if (_seenMsgIds.contains(msg.msgId)) return;
          _markSeen(msg.msgId);
          
          // Process locally
          _handleMessage(msg);
          
          // Flood-Relay: Forward to all OTHER channels
          for (final c in _channels) {
            if (c != ws) {
              try { c.sink.add(jsonStr); } catch (_) {}
            }
          }
        } catch (_) {}
      },
      onDone: () {
        _channels.remove(ws);
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  void _markSeen(String id) {
    _seenMsgIds.add(id);
    if (_seenMsgIds.length > _maxSeenIds) {
      _seenMsgIds.removeAt(0);
    }
  }

  // ── Outbound Broadcast ───────────────────────────────────────────────────
  /// Broadcast a message originating from THIS device
  void broadcast(PeerMessage msg) {
    if (!isActive) return;
    
    _markSeen(msg.msgId); // don't echo back to ourselves
    final jsonStr = msg.toJsonString();
    
    for (final c in _channels) {
      try { c.sink.add(jsonStr); } catch (_) {}
    }
  }

  void broadcastMyLocation(double lat, double lng, double heading) {
    if (!isActive) return;
    broadcast(PeerMessage.location(from: myName, lat: lat, lng: lng, heading: heading));
  }
  
  void addOwnChat(String text) {
    final msg = PeerMessage.chat(from: myName, text: text);
    chatMessages.add(msg);
    broadcast(msg);
    notifyListeners();
  }

  void clearUnread() {
    unreadChat = 0;
    notifyListeners();
  }

  // ── Message Handler ──────────────────────────────────────────────────────
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
      case PeerMessageType.alert:
        chatMessages.add(msg);
        unreadChat++;
      case PeerMessageType.bye:
        peerLocations.remove(msg.from);
        peerHeadings.remove(msg.from);
        peerLastSeen.remove(msg.from);
      case PeerMessageType.ping:
      case PeerMessageType.marker:
      case PeerMessageType.roster:
        break;
    }
    notifyListeners();
  }

  // ── Stop ─────────────────────────────────────────────────────────────────
  Future<void> stop() async {
    if (!isActive) return;
    broadcast(PeerMessage.bye(from: myName));
    
    for (final c in _channels) {
      await c.sink.close();
    }
    _channels.clear();
    
    await _httpServer?.close(force: true);
    _httpServer = null;
    
    isActive = false;
    myName = '';
    localServerAddress = '';
    peerLocations.clear();
    peerHeadings.clear();
    peerLastSeen.clear();
    chatMessages.clear();
    unreadChat = 0;
    _seenMsgIds.clear();
    notifyListeners();
  }

  int get connectedNodesCount => _channels.length;
  List<String> get activePeers => peerLocations.keys.toList();

  static Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
