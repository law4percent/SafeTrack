// lib/screens/ask_ai_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/gemini_service.dart';

class AskAIScreen extends StatefulWidget {
  const AskAIScreen({super.key});

  @override
  State<AskAIScreen> createState() => _AskAIScreenState();
}

class _AskAIScreenState extends State<AskAIScreen> {
  final TextEditingController _questionController = TextEditingController();
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
      final response = await _geminiService.sendMessage(question);
      if (!mounted) return;

      // 429 rate-limit — surface a friendly prompt and open model picker
      if (response == kGeminiRateLimitError) {
        setState(() {
          _conversation.add({
            'type': 'ai',
            'content':
                '⚠️ This assistant has reached its usage limit for now.\n\n'
                'Tap **Switch Assistant** below to pick another one — '
                'your question will be ready to resend.',
            'time': DateTime.now(),
          });
          _isLoading = false;
        });
        _scrollToBottom();
        // Small delay so the message is visible before the sheet opens
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _showModelPicker();
        return;
      }

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
          'content': 'Sorry, I encountered an error. Please try again.',
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // ── Model picker ──────────────────────────────────────────────
  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModelPickerSheet(
        geminiService: _geminiService,
        onModelSelected: (model) {
          // Reset conversation when switching — clean slate per model
          setState(() => _conversation.clear());
          _geminiService.resetConversation();
          _geminiService.setModel(model);
          setState(() {}); // Rebuild banner + AppBar subtitle
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentModel = _geminiService.selectedModel;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ask AI Assistant',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${currentModel.displayName} · ${currentModel.id}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          // Model switcher — brain icon, non-technical tooltip
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'Switch AI assistant',
            onPressed: _showModelPicker,
          ),
          // Reset conversation
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
          // ── Info banner ────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: Colors.blue[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Using ${currentModel.displayName} (${currentModel.id}) · Reads your real device data',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _showModelPicker,
                  child: Text(
                    'Change',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Conversation ───────────────────────────────────────
          Expanded(
            child: _conversation.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        _conversation.length + (_isLoading ? 1 : 0),
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

          // ── Input area ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border:
                  Border(top: BorderSide(color: Colors.grey[300]!)),
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
                      contentPadding: const EdgeInsets.symmetric(
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send, color: Colors.blue[800]),
                  onPressed: _isLoading
                      ? null
                      : () => _askAI(_questionController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 60, color: Colors.blue[300]),
            const SizedBox(height: 16),
            const Text(
              'Ask me anything!',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'I have access to your children\'s real-time data',
              style:
                  TextStyle(color: Colors.grey[600], fontSize: 13),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              style:
                  TextStyle(color: Colors.blue[900], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message bubble ────────────────────────────────────────────
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
                            p: TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              height: 1.5,
                            ),
                            strong: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            em: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.black87,
                            ),
                            listBullet: TextStyle(
                              color: Colors.blue[800],
                              fontSize: 14,
                            ),
                            code: TextStyle(
                              backgroundColor: Colors.grey[200],
                              color: Colors.blue[900],
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
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

  // ── Loading bubble ────────────────────────────────────────────
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

// =============================================================
// MODEL PICKER BOTTOM SHEET
// Parent-friendly UI — no API IDs, no technical terms visible.
// =============================================================
class _ModelPickerSheet extends StatefulWidget {
  final GeminiService geminiService;
  final void Function(GeminiModel model) onModelSelected;

  const _ModelPickerSheet({
    required this.geminiService,
    required this.onModelSelected,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  late GeminiModel _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.geminiService.selectedModel;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.psychology_outlined,
                    color: Colors.blue[800], size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose AI Assistant',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'If one stops responding, switch to another.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Model cards
          ...kGeminiModels.map((m) => _buildModelCard(m)),

          const SizedBox(height: 8),

          // Plain-English quota note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber[200]!),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Each assistant has a daily usage limit. '
                    'If the AI stops responding or shows an error, '
                    'simply pick a different one here — your conversation '
                    'will restart fresh.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.amber[900]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onModelSelected(_pending);
              },
              child: Text(
                _pending.id ==
                        widget.geminiService.selectedModel.id
                    ? 'Keep Current Assistant'
                    : 'Switch to ${_pending.displayName}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(GeminiModel model) {
    final isSelected = _pending.id == model.id;
    final isActive =
        widget.geminiService.selectedModel.id == model.id;

    // Badge → color mapping
    final badgeColor = <String, Color>{
          'Fastest': Colors.green,
          'Recommended': Colors.blue,
          'Most Accurate': Colors.purple,
        }[model.badge] ??
        Colors.grey;

    // Speed dots: Fastest = 3, Recommended = 2, Most Accurate = 1
    final dots = <String, int>{
          'Fastest': 3,
          'Recommended': 2,
          'Most Accurate': 1,
        }[model.badge] ??
        1;

    return GestureDetector(
      onTap: () => setState(() => _pending = model),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.blue[700]!
                : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Colors.blue[700]!
                      : Colors.grey[400]!,
                  width: 2,
                ),
                color: isSelected
                    ? Colors.blue[700]
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 13)
                  : null,
            ),
            const SizedBox(width: 12),

            // Card content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + badges row
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        model.displayName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.blue[900]
                              : Colors.black87,
                        ),
                      ),
                      // Type badge
                      _chip(model.badge, badgeColor),
                      // Currently active indicator
                      if (isActive) _chip('Active', Colors.green),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model.description,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 7),
                  // Speed dots + plain-English quota
                  Row(
                    children: [
                      ...List.generate(
                        3,
                        (i) => Container(
                          width: 8,
                          height: 8,
                          margin:
                              const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < dots
                                ? badgeColor
                                : Colors.grey[300],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        model.quota,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}