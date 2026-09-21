import 'package:flutter/material.dart';
import '../../../core/models/peer_message.dart';
import '../../../core/services/peer_session.dart';
import '../../../shared/theme.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    final session = PeerSession.instance;
    session.sendMessage(PeerMessage.chat(from: session.myName, text: txt));
    session.addOwnChat(txt);
    _ctrl.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PeerSession.instance,
      builder: (context, _) {
        final session = PeerSession.instance;
        final messages = session.chatMessages;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12132A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderBright),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1F3A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: AppTheme.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('Team Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${session.members.length + 1} online',
                        style: const TextStyle(color: AppTheme.greenAccent, fontSize: 12)),
                  ],
                ),
              ),
              // Messages list
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Text('No messages yet.\nSay hello! 👋',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(10),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _MessageBubble(
                          msg: messages[i],
                          isMine: messages[i].from == session.myName,
                        ),
                      ),
              ),
              // Input
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
                          hintText: 'Type a message...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF262740),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'chat_send',
                      backgroundColor: AppTheme.greenAccent,
                      onPressed: _send,
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
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
    final isAlert = msg.type == PeerMessageType.alert;
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
              child: Text(msg.from, style: const TextStyle(color: AppTheme.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          Row(
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isAlert
                      ? const Color(0xFF7B1F1F)
                      : isMine
                          ? const Color(0xFF1F6B3B)
                          : const Color(0xFF252545),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isAlert)
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
                        const SizedBox(width: 4),
                        Text(msg.level?.toUpperCase() ?? 'ALERT',
                            style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                      ]),
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
