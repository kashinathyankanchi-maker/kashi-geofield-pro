import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../shared/theme.dart';
import 'gemini_service.dart';

class GeminiChatScreen extends StatefulWidget {
  final String pdfTitle;
  final String pdfAssetPath;

  const GeminiChatScreen({
    super.key,
    required this.pdfTitle,
    required this.pdfAssetPath,
  });

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final TextEditingController _questionCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<Map<String, String>> _messages = [];
  String _pdfText = '';
  bool _isLoading = false;
  bool _isExtractingText = true;
  String? _apiKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Load API key — use saved preference
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('settings_gemini_api_key') ?? '';

    if (_apiKey == null || _apiKey!.isEmpty) {
      setState(() {
        _isExtractingText = false;
        _error = 'No Gemini API Key found.\n\nGo to Settings → Gemini AI Key and paste your key.\n\nGet a FREE key at: aistudio.google.com';
      });
      return;
    }

    // Extract text from PDF
    try {
      final data = await rootBundle.load(widget.pdfAssetPath);
      final bytes = data.buffer.asUint8List();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);

      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        buffer.writeln(pageText);
      }
      document.dispose();

      _pdfText = buffer.toString();

      // Trim to ~30,000 chars to fit Gemini context limits
      if (_pdfText.length > 30000) {
        _pdfText = _pdfText.substring(0, 30000);
      }

      setState(() {
        _isExtractingText = false;
        _messages.add({
          'role': 'model',
          'text': 'I have read "${widget.pdfTitle}". Ask me any question about this document! 📖',
        });
      });
    } catch (e) {
      setState(() {
        _isExtractingText = false;
        _error = 'Failed to extract text from PDF: $e';
      });
    }
  }

  Future<void> _sendQuestion() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'role': 'user', 'text': question});
      _isLoading = true;
    });
    _questionCtrl.clear();
    _scrollToBottom();

    final service = GeminiService(apiKey: _apiKey!);

    // Build history (skip the first welcome message)
    final history = _messages
        .where((m) => m['role'] == 'user' || (m['role'] == 'model' && _messages.indexOf(m) > 0))
        .toList();
    // Remove the last user message since we pass it separately
    if (history.isNotEmpty && history.last['role'] == 'user') {
      history.removeLast();
    }

    final answer = await service.askQuestion(
      pdfText: _pdfText,
      question: question,
      chatHistory: history,
    );

    setState(() {
      _messages.add({'role': 'model', 'text': answer});
      _isLoading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.pdfTitle,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A237E), // deep blue for AI
        foregroundColor: Colors.white,
        actions: [
          if (_messages.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear chat',
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _messages.add({
                    'role': 'model',
                    'text': 'Chat cleared. Ask me a new question about "${widget.pdfTitle}"! 📖',
                  });
                });
              },
            ),
        ],
      ),
      body: _isExtractingText
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.greenAccent),
                  const SizedBox(height: 16),
                  Text('Reading PDF...', style: AppTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Text('Extracting text from document', style: AppTheme.bodySmall),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.vpn_key_off_rounded, size: 64, color: Colors.orange.shade300),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: AppTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // ── Chat Messages ──
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoading && index == _messages.length) {
                            return _buildTypingIndicator();
                          }
                          final msg = _messages[index];
                          final isUser = msg['role'] == 'user';
                          return _buildMessageBubble(msg['text']!, isUser);
                        },
                      ),
                    ),

                    // ── Input Bar ──
                    Container(
                      padding: EdgeInsets.only(
                        left: 12,
                        right: 8,
                        top: 8,
                        bottom: MediaQuery.of(context).padding.bottom + 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        border: Border(top: BorderSide(color: AppTheme.borderColor)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _questionCtrl,
                              focusNode: _focusNode,
                              style: AppTheme.bodyMedium,
                              maxLines: 3,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendQuestion(),
                              decoration: InputDecoration(
                                hintText: 'Ask a question...',
                                hintStyle: TextStyle(color: AppTheme.textMuted),
                                filled: true,
                                fillColor: AppTheme.bgSurface,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1A237E), Color(0xFF4A148C)],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.send_rounded, color: Colors.white),
                              onPressed: _isLoading ? null : _sendQuestion,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF1A237E),
              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF1A237E) : AppTheme.bgCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: AppTheme.borderColor),
              ),
              child: SelectableText(
                text,
                style: AppTheme.bodyMedium.copyWith(
                  color: isUser ? Colors.white : AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.greenPrimary,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF1A237E),
            child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
