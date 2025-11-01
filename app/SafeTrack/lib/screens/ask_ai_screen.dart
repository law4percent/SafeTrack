import 'package:flutter/material.dart';
import '../services/gemini_service.dart';

class AskAIScreen extends StatefulWidget {
  const AskAIScreen({super.key});

  @override
  State<AskAIScreen> createState() => _AskAIScreenState();
}

class _AskAIScreenState extends State<AskAIScreen> {
  final TextEditingController _questionController = TextEditingController();
  final List<Map<String, dynamic>> _conversation = [];
  final GeminiService _geminiService = GeminiService();
  bool _isLoading = false;

  void _askAI(String question) async {
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

    try {
      final response = await _geminiService.getResponse(question);
      
      setState(() {
        _conversation.add({
          'type': 'ai',
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _conversation.add({
          'type': 'ai',
          'content': 'Sorry, I encountered an error. Please try again.',
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask AI Assistant'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: Colors.blue[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Assistant - Powered by Gemini',
                    style: TextStyle(color: Colors.blue[800], fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          
          // Conversation
          Expanded(
            child: _conversation.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 60, color: Colors.blue[300]),
                        const SizedBox(height: 16),
                        const Text(
                          'Ask me anything!',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            children: [
                              Text(
                                'Try asking:',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 8),
                              _buildSuggestionChip('How is my child?'),
                              const SizedBox(height: 4),
                              _buildSuggestionChip('Who made this app?'),
                              const SizedBox(height: 4),
                              _buildSuggestionChip('Safety tips for children'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    reverse: true,
                    itemCount: _conversation.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == 0) {
                        return _buildLoadingMessage();
                      }
                      
                      final messageIndex = _isLoading ? index - 1 : index;
                      final message = _conversation[_conversation.length - 1 - messageIndex];
                      return _buildMessageBubble(message);
                    },
                  ),
          ),
          
          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      hintText: 'Type your question here...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _askAI,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.blue[800]),
                  onPressed: () => _askAI(_questionController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return GestureDetector(
      onTap: () => _askAI(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline, size: 16, color: Colors.blue[700]),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(color: Colors.blue[900], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isUser = message['type'] == 'user';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.blue[800],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[100] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message['content'],
                style: TextStyle(
                  color: isUser ? Colors.blue[900] : Colors.black87,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.blue[800],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Thinking...'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }
}