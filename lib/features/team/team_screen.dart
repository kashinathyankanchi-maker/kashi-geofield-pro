import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/peer_message.dart';
import '../../core/services/peer_session.dart';
import '../../shared/theme.dart';
import 'widgets/chat_panel.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadSavedName();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('team_my_name') ?? '';
    if (saved.isNotEmpty) _nameCtrl.text = saved;
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('team_my_name', name);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  // ── Host ──────────────────────────────────────────────────────────────────

  Future<void> _startHost() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter your name'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await _saveName(name);
      await PeerSession.instance.startAsHost(name);
    } catch (e) {
      setState(() => _error = 'Failed to start: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Join ──────────────────────────────────────────────────────────────────

  Future<void> _joinSession() async {
    final name = _nameCtrl.text.trim();
    final address = _ipCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter your name'); return; }
    if (address.isEmpty) { setState(() => _error = 'Enter host IP:port'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await _saveName(name);
      await PeerSession.instance.joinAsClient(name, address);
    } catch (e) {
      setState(() => _error = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stopSession() async {
    await PeerSession.instance.stop();
    setState(() {});
  }

  // ── QR Scan ───────────────────────────────────────────────────────────────

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanPage()),
    );
    if (result != null) setState(() => _ipCtrl.text = result);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AppTheme.bgSecondary,
          title: const Text('Team Collaboration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: AppTheme.greenAccent,
            labelColor: AppTheme.greenAccent,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(icon: Icon(Icons.wifi_tethering), text: 'Host Session'),
              Tab(icon: Icon(Icons.group_add), text: 'Join Session'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: PeerSession.instance,
          builder: (context, _) {
            final session = PeerSession.instance;
            if (session.isActive) return _activeSessionView(session);
            return TabBarView(
              controller: _tabs,
              children: [_hostSetupView(), _joinSetupView()],
            );
          },
        ),
      ),
    );
  }

  // ── Active Session ────────────────────────────────────────────────────────

  Widget _activeSessionView(PeerSession session) {
    return Column(
      children: [
        // Status banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: session.role == SessionRole.host
              ? const Color(0xFF1B3A2A)
              : const Color(0xFF1A2A3A),
          child: Row(
            children: [
              Icon(
                session.role == SessionRole.host ? Icons.wifi_tethering : Icons.link,
                color: AppTheme.greenAccent, size: 20,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.role == SessionRole.host ? 'Hosting as ${session.myName}' : 'Connected as ${session.myName}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    session.role == SessionRole.host
                        ? '${session.members.length} member(s) connected'
                        : 'Host: ${session.hostAddress}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _stopSession,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                label: const Text('Stop', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),

        // QR Code (host only)
        if (session.role == SessionRole.host)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              color: const Color(0xFF1E1F3A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Members scan this QR to connect',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: session.serverAddress,
                      version: QrVersions.auto,
                      size: 160,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(session.serverAddress,
                        style: const TextStyle(color: AppTheme.greenAccent, fontSize: 13, fontFamily: 'monospace')),
                    const SizedBox(height: 4),
                    const Text('Or type this address on member devices',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),

        // Members list (host only)
        if (session.role == SessionRole.host && session.members.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              color: const Color(0xFF1E1F3A),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Connected Members', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  ),
                  ...session.members.map((m) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppTheme.greenAccent,
                      child: Text(m[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    title: Text(m, style: const TextStyle(color: Colors.white)),
                    trailing: const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                  )),
                ],
              ),
            ),
          ),

        // Chat
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: const ChatPanel(),
          ),
        ),
      ],
    );
  }

  // ── Setup Views ───────────────────────────────────────────────────────────

  Widget _nameField() => TextField(
    controller: _nameCtrl,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: 'Your Name',
      labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: const Icon(Icons.person, color: AppTheme.greenAccent),
      filled: true,
      fillColor: const Color(0xFF1E1F3A),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );

  Widget _hostSetupView() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.wifi_tethering,
          title: 'You are the Team Leader',
          body: 'Enable your phone\'s WiFi Hotspot first, then tap "Start Session". Other team members connect to your hotspot and join.',
        ),
        const SizedBox(height: 20),
        _nameField(),
        const SizedBox(height: 16),
        if (_error != null) _errorWidget(),
        ElevatedButton.icon(
          onPressed: _loading ? null : _startHost,
          icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow_rounded),
          label: const Text('Start Session'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.greenAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );

  Widget _joinSetupView() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.group_add,
          title: 'Join Your Team Leader',
          body: 'Connect to the Team Leader\'s WiFi Hotspot first, then scan their QR code or enter their IP address manually.',
        ),
        const SizedBox(height: 20),
        _nameField(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Host IP:Port  e.g. 192.168.43.1:8765',
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                  prefixIcon: const Icon(Icons.lan, color: AppTheme.greenAccent),
                  filled: true,
                  fillColor: const Color(0xFF1E1F3A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0xFF1E1F3A),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _scanQr,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(Icons.qr_code_scanner, color: AppTheme.greenAccent, size: 28),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null) _errorWidget(),
        ElevatedButton.icon(
          onPressed: _loading ? null : _joinSession,
          icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.login_rounded),
          label: const Text('Join Session'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );

  Widget _errorWidget() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
  );

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
            Icon(icon, color: AppTheme.greenAccent, size: 26),
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
        title: const Text('Scan Host QR Code', style: TextStyle(color: Colors.white)),
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
