
import 'package:flutter/material.dart';

const chatTeal = Color(0xFF187D8A);

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final List<Map<String, String>> _messages = [
    {
      'role': 'bot',
      'text':
          'Hello! 👋 I’m your Rehab Assistant. '
          'I can help you use RehabSudoku. What would you like to know?'
    },
  ];

  final List<String> _questions = [
    'How do I start?',
    'What is the warm-up?',
    'What is reaction time?',
    'How do I finish a session?',
  ];

  String _getAnswer(String question) {
    final q = question.toLowerCase();

    if (q.contains('start') || q.contains('begin')) {
      return 'To begin, go to the home screen and follow the '
          'instructions to complete your warm-up before starting '
          'your training session.';
    }

    if (q.contains('warm') || q.contains('light chase')) {
      return 'The warm-up prepares you for your training. '
          'Follow the Light Chase prompts on the screen and '
          'complete the tasks at your own pace.';
    }

    if (q.contains('reaction') || q.contains('time')) {
      return 'Reaction time measures how long you take to respond '
          'to a prompt. Your recorded result describes performance '
          'during that session; it is not a medical diagnosis.';
    }

    if (q.contains('finish') || q.contains('cool') ||
        q.contains('end session')) {
      return 'Follow the in-app instructions to complete your '
          'training and cool-down. Review your session summary '
          'when it becomes available.';
    }

    if (q.contains('help') || q.contains('what can you do')) {
      return 'I can explain the warm-up, training, cool-down, '
          'reaction time, and how to navigate RehabSudoku.';
    }

    return 'I’m not sure I understand that question yet. '
        'Try asking about starting a session, the warm-up, '
        'reaction time, or the cool-down.';
  }

  void _sendMessage([String? suggestedQuestion]) {
    final question =
        (suggestedQuestion ?? _controller.text).trim();

    if (question.isEmpty) return;

    setState(() {
      _messages.add({
        'role': 'user',
        'text': question,
      });

      _messages.add({
        'role': 'bot',
        'text': _getAnswer(question),
      });
    });

    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: chatTeal,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                Icons.support_agent,
                color: chatTeal,
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rehab Assistant',
                  style: TextStyle(fontSize: 18),
                ),
                Text(
                  'Here to help you',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isUser = message['role'] == 'user';

                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.8,
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isUser
                            ? chatTeal
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: isUser
                            ? null
                            : Border.all(
                                color: Colors.black12,
                              ),
                      ),
                      child: Text(
                        message['text']!,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: isUser
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _questions.map((question) {
                  return ActionChip(
                    label: Text(question),
                    onPressed: () => _sendMessage(question),
                  );
                }).toList(),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _sendMessage(),
                    style: IconButton.styleFrom(
                      backgroundColor: chatTeal,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send),
                    tooltip: 'Send message',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
