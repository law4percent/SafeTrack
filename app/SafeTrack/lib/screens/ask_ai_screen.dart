// app/SafeTrack/lib/screens/ask_ai_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // ✅ NEW
import '../services/gemini_service.dart';

class AskAIScreen extends StatefulWidget {
  const AskAIScreen({super.key});

  @override
  State<AskAIScreen> createState() => _AskAIScreenState();
}

class _AskAIScreenState extends State<AskAIScreen> {
  final TextEditingController _questionController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _conversation = [];
  final GeminiService _geminiService = GeminiService();
  bool _isLoading = false;

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _askAI(String question) async {
    if (question.trim().isEmpty) return;

    setState(() {
      _conversation.add({
        'type': 'user',
        'content': question,
        'time': DateTime.now(),
      });
      _isLoading = true;
    });

    _questionController.clear();
    _scrollToBottom();

    try {
      // ✅ FIXED: was getResponse(), correct method is sendMessage()
      final response = await _geminiService.sendMessage(question);

      if (!mounted) return;
      setState(() {
        _conversation.add({
          'type': 'ai',
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conversation.add({
          'type': 'ai',
          'content':
              'Sorry, I encountered an error. Please try again.',
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask AI Assistant'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          // Reset conversation button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New conversation',
            onPressed: () {
              setState(() => _conversation.clear());
              _geminiService.resetConversation();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 20, color: Colors.blue[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Assistant — Powered by Gemini · Uses your real device data',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Conversation
          Expanded(
            child: _conversation.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _conversation.length +
                        (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading &&
                          index == _conversation.length) {
                        return _buildLoadingMessage();
                      }
                      return _buildMessageBubble(
                          _conversation[index]);
                    },
                  ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                  top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: _isLoading
                          ? 'Thinking...'
                          : 'Ask about your child\'s status...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: _isLoading ? null : _askAI,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                      : Icon(Icons.send,
                          color: Colors.blue[800]),
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _askAI(_questionController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome,
                size: 60, color: Colors.blue[300]),
            const SizedBox(height: 16),
            const Text(
              'Ask me anything!',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'I have access to your children\'s real-time data',
              style: TextStyle(
                  color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text('Try asking:',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip('Where is my child?'),
                _buildSuggestionChip('Is anyone\'s SOS active?'),
                _buildSuggestionChip('Check battery levels'),
                _buildSuggestionChip('Is my child online?'),
                _buildSuggestionChip('Has my child arrived at school?'),
                _buildSuggestionChip('Who made this app?'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return GestureDetector(
      onTap: () => _askAI(text),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline,
                size: 14, color: Colors.blue[700]),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                  color: Colors.blue[900], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message bubble ───────────────────────────────────────────
  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isUser = message['type'] == 'user';
    final time = message['time'] as DateTime;
    final timeString =
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue[800],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Colors.blue[100]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft:
                          Radius.circular(isUser ? 12 : 0),
                      bottomRight:
                          Radius.circular(isUser ? 0 : 12),
                    ),
                  ),
                  // ✅ USER bubble: plain Text (no markdown needed)
                  // ✅ AI bubble: MarkdownBody renders **bold**,
                  //    bullet lists, headers correctly
                  child: isUser
                      ? Text(
                          message['content'],
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontSize: 14,
                            height: 1.4,
                          ),
                        )
                      : MarkdownBody(
                          data: message['content'],
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            // Body text
                            p: TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              height: 1.5,
                            ),
                            // Bold
                            strong: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            // Italic
                            em: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.black87,
                            ),
                            // Bullet list items
                            listBullet: TextStyle(
                              color: Colors.blue[800],
                              fontSize: 14,
                            ),
                            // Code blocks
                            code: TextStyle(
                              backgroundColor:
                                  Colors.grey[200],
                              color: Colors.blue[900],
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            // Spacing between paragraphs
                            blockSpacing: 8,
                          ),
                        ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue[800],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person,
                      color: Colors.white, size: 16),
                ),
              ],
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isUser ? 0 : 40,
              right: isUser ? 40 : 0,
            ),
            child: Text(
              timeString,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading bubble ───────────────────────────────────────────
  Widget _buildLoadingMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue[800],
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue[800],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Checking your device data...',
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}