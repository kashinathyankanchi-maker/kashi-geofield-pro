import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/models/peer_message.dart';

/// WebSocket client — connects to the host phone running [PeerServer].
class PeerClient {
  WebSocketChannel? _channel;
  final StreamController<PeerMessage> _inbound = StreamController.broadcast();

  Stream<PeerMessage> get messages => _inbound.stream;
  bool get isConnected => _channel != null;

  /// Connect to [hostAddress] e.g. "192.168.43.1:8765".
  /// Throws on failure.
  Future<void> connect(String hostAddress, String myName) async {
    final uri = Uri.parse('ws://$hostAddress');
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _channel!.stream.listen(
      (data) {
        try {
          final msg = PeerMessage.fromJsonString(data as String);
          _inbound.add(msg);
        } catch (_) {}
      },
      onDone: disconnect,
      cancelOnError: true,
    );

    // Announce ourselves
    send(PeerMessage.ping(from: myName));
  }

  /// Send a message to the host (which relays to all peers).
  void send(PeerMessage msg) {
    try {
      _channel?.sink.add(msg.toJsonString());
    } catch (_) {}
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
  }
}
