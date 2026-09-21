import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/peer_message.dart';
import '../../core/services/mesh_session.dart';
import '../../shared/theme.dart';
import 'widgets/chat_panel.dart'; // We will use a modified ChatPanel or just re-use the UI

class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});
  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('mesh_my_name') ?? '';
    if (saved.isNotEmpty) _nameCtrl.text = saved;
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mesh_my_name', name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _startNode() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter your name'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await _saveName(name);
      await MeshSession.instance.startNode(name);
    } catch (e) {
      setState(() => _error = 'Failed to start node: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectToNode() async {
    final address = _ipCtrl.text.trim();
    if (address.isEmpty) { setState(() => _error = 'Enter node IP:port'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await MeshSession.instance.connectToNode(address);
      _ipCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected to node!'), backgroundColor: Colors.green));
    } catch (e) {
      setState(() => _error = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stopNode() async {
    await MeshSession.instance.stop();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanPage()),
    );
    if (result != null) {
      _ipCtrl.text = result;
      _connectToNode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AppTheme.bgSecondary,
          title: const Text('Mesh Network', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: ListenableBuilder(
          listenable: MeshSession.instance,
          builder: (context, _) {
            final session = MeshSession.instance;
            if (session.isActive) return _activeMeshView(session);
            return _setupView();
          },
        ),
      ),
    );
  }

  Widget _setupView() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.hub_rounded,
          title: 'Start Mesh Node',
          body: 'Turn on your WiFi Hotspot OR connect to a team member\'s Hotspot, then Start your Node. You will automatically relay messages.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Your Name',
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.person, color: Colors.orangeAccent),
            filled: true,
            fillColor: const Color(0xFF1E1F3A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
        ElevatedButton.icon(
          onPressed: _loading ? null : _startNode,
          icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.power_settings_new),
          label: const Text('Start My Node'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );

  Widget _activeMeshView(MeshSession session) {
    return Column(
      children: [
        // Status banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF3E2723), // brown tone for mesh
          child: Row(
            children: [
              const Icon(Icons.hub_rounded, color: Colors.orangeAccent, size: 24),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mesh Node Active: ${session.myName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('${session.connectedNodesCount} direct link(s) • ${session.activePeers.length} peer(s) in mesh', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _stopNode,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                label: const Text('Stop', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),

        // IP and Connection Box
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // My QR
              Expanded(
                child: Card(
                  color: const Color(0xFF1E1F3A),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('My Node Address', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        QrImageView(data: session.localServerAddress, version: QrVersions.auto, size: 80, backgroundColor: Colors.white),
                        const SizedBox(height: 4),
                        SelectableText(session.localServerAddress, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Connect Box
              Expanded(
                flex: 2,
                child: Card(
                  color: const Color(0xFF1E1F3A),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add Mesh Link', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ipCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'IP:Port',
                                  hintStyle: TextStyle(color: Colors.white38),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Color(0xFF262740),
                                  border: OutlineInputBorder(borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: _scanQr,
                              icon: const Icon(Icons.qr_code_scanner, color: Colors.orangeAccent),
                              tooltip: 'Scan QR',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _connectToNode,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
                            child: const Text('Connect'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Peers in Mesh
        if (session.activePeers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Peers in Mesh: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Expanded(
                  child: Text(
                    session.activePeers.join(', '),
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Chat
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _MeshChatPanel(),
          ),
        ),
      ],
    );
  }

  Widget _infoCard({required IconData icon, required String title, required String body}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1B30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderBright),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.orangeAccent, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── QR Scanner Page ─────────────────────────────────────────────────────────
class _QrScanPage extends StatelessWidget {
  const _QrScanPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Node QR Code', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          if (barcode?.rawValue != null) {
            Navigator.pop(context, barcode!.rawValue);
          }
        },
      ),
    );
  }
}

// ── Mesh Chat Panel ─────────────────────────────────────────────────────────
class _MeshChatPanel extends StatefulWidget {
  @override
  State<_MeshChatPanel> createState() => _MeshChatPanelState();
}

class _MeshChatPanelState extends State<_MeshChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  void _send() {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    MeshSession.instance.addOwnChat(txt);
    _ctrl.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MeshSession.instance,
      builder: (context, _) {
        final session = MeshSession.instance;
        final messages = session.chatMessages;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12132A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('Mesh Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${messages.length} msgs', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('No mesh messages yet.', style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(10),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final msg = messages[i];
                          final isMine = msg.from == session.myName;
                          return _MessageBubble(msg: msg, isMine: isMine);
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
                color: const Color(0xFF1A1B30),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Type to mesh...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF262740),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'mesh_chat_send',
                      backgroundColor: Colors.orangeAccent,
                      onPressed: _send,
                      child: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final PeerMessage msg;
  final bool isMine;
  const _MessageBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(msg.ts);
    final timeStr = '${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(msg.from, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          Row(
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMine ? const Color(0xFF795548) : const Color(0xFF252545),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg.text ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
