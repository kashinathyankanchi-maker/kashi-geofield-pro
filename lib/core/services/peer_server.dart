import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/models/peer_message.dart';

/// Runs a WebSocket server on [port] so other devices can connect over LAN.
/// The host phone must be a WiFi hotspot or on the same WiFi network.
class PeerServer {
  static const int port = 8765;

  HttpServer? _httpServer;
  final Map<String, WebSocketChannel> _clients = {}; // name → channel
  final StreamController<PeerMessage> _inbound = StreamController.broadcast();

  /// Stream of messages received from any client.
  Stream<PeerMessage> get messages => _inbound.stream;

  /// List of connected member names.
  List<String> get memberNames => List.unmodifiable(_clients.keys);

  bool get isRunning => _httpServer != null;

  /// Start the WebSocket server. Returns the local IP:port string.
  Future<String> start() async {
    final handler = webSocketHandler((WebSocketChannel ws, _) {
      String? peerName;

      ws.stream.listen(
        (data) {
          try {
            final msg = PeerMessage.fromJsonString(data as String);
            peerName ??= msg.from;

            if (msg.type == PeerMessageType.bye) {
              _clients.remove(msg.from);
              _broadcastRoster(excludeName: msg.from);
              ws.sink.close();
              return;
            }

            _clients[msg.from] = ws;
            _inbound.add(msg);

            // Relay to all OTHER clients
            _relayToOthers(data, excludeName: msg.from);

            // After a ping, send updated roster to all
            if (msg.type == PeerMessageType.ping) {
              _broadcastRoster();
            }
          } catch (_) {}
        },
        onDone: () {
          if (peerName != null) {
            _clients.remove(peerName);
            _broadcastRoster(excludeName: peerName);
          }
        },
        cancelOnError: true,
      );
    });

    _httpServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    final ip = await _getLocalIp();
    return '$ip:$port';
  }

  void _relayToOthers(String data, {String? excludeName}) {
    for (final entry in _clients.entries) {
      if (entry.key != excludeName) {
        try {
          entry.value.sink.add(data);
        } catch (_) {}
      }
    }
  }

  void _broadcastRoster({String? excludeName}) {
    final names = _clients.keys.toList();
    final rosterMsg = PeerMessage.roster(from: 'server', members: names).toJsonString();
    for (final entry in _clients.entries) {
      if (entry.key != excludeName) {
        try {
          entry.value.sink.add(rosterMsg);
        } catch (_) {}
      }
    }
  }

  /// Broadcast a message from the HOST to all connected clients.
  void broadcast(PeerMessage msg) {
    final s = msg.toJsonString();
    _inbound.add(msg);
    _relayToOthers(s);
  }

  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
    _clients.clear();
  }

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
