import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http_parser/http_parser.dart'; // Needed for MediaType
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
// Removed: import 'package:flutter_spinkit/flutter_spinkit.dart';

const String kBackendUrl = 'https://dash-gem-ef3cd0583e98.herokuapp.com/analyzeDashboardPic';

// Some colors for the wave background:
const Color kColorPrimary = Color(0xFF3D8D7A);
const Color kColorLightGreen = Color(0xFFB3D8A8);
const Color kColorCream = Color(0xFFFBFFE4);
const Color kColorMint = Color(0xFFA3D1C6);

enum MessageSender { user, ai }

class ChatMessage {
  final MessageSender sender;
  final String text;
  final Uint8List? imageBytes;
  final DateTime timeStamp;
  bool isLiked;

  ChatMessage({
    required this.sender,
    this.text = '',
    this.imageBytes,
    required this.timeStamp,
    this.isLiked = false,
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DashGemChatApp());
}

class DashGemChatApp extends StatelessWidget {
  const DashGemChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dash-gem',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: kColorPrimary,
        scaffoldBackgroundColor: kColorCream,
      ),
      home: const DashGemChatPage(),
    );
  }
}

class DashGemChatPage extends StatefulWidget {
  const DashGemChatPage({Key? key}) : super(key: key);

  @override
  State<DashGemChatPage> createState() => _DashGemChatPageState();
}

class _DashGemChatPageState extends State<DashGemChatPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _textCtrl = TextEditingController();

  late AnimationController _waveController;

  List<ChatMessage> _messages = [];
  bool _isSending = false;
  bool _aiTyping = false;
  bool _showScrollDownBtn = false;

  Uint8List? _selectedImageBytes;   // Held until user hits "Send"
  Uint8List? _imagePreviewBytes;    // For full-screen preview on tap

  @override
  void initState() {
    super.initState();

    // Start wave animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Initial sample message
    _messages = [
      ChatMessage(
        sender: MessageSender.ai,
        text: "Hello, how can I help you?",
        timeStamp: DateTime.now(),
      ),
    ];

    _scrollCtrl.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _textCtrl.dispose();
    _scrollCtrl.removeListener(_onScrollChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    final distanceFromBottom =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels;
    bool shouldShow = distanceFromBottom > 150;
    if (shouldShow != _showScrollDownBtn) {
      setState(() {
        _showScrollDownBtn = shouldShow;
      });
    }
  }

  void _clearChat() {
    setState(() {
      _messages = [
        ChatMessage(
          sender: MessageSender.ai,
          text: "Hello, how can I help you?",
          timeStamp: DateTime.now(),
        ),
      ];
      _selectedImageBytes = null;
      _textCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // Keep only last 10 messages + new
  String _buildConversationMemory() {
    const maxMemoryCount = 10;
    int startIndex = _messages.length - maxMemoryCount;
    if (startIndex < 0) startIndex = 0;

    final recentMessages = _messages.sublist(startIndex);

    final buffer = StringBuffer();
    for (final msg in recentMessages) {
      final speaker = (msg.sender == MessageSender.user) ? 'User' : 'AI';
      if (msg.imageBytes != null) {
        buffer.writeln('$speaker: [image attached]');
      }
      if (msg.text.isNotEmpty) {
        buffer.writeln('$speaker: ${msg.text}');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  void _addUserMessage({String text = '', Uint8List? imageBytes}) {
    setState(() {
      _messages.add(ChatMessage(
        sender: MessageSender.user,
        text: text,
        imageBytes: imageBytes,
        timeStamp: DateTime.now(),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _addAIMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        sender: MessageSender.ai,
        text: text,
        timeStamp: DateTime.now(),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _handleSendText() {
    final text = _textCtrl.text.trim();
    // If user typed nothing & no image, do nothing
    if (text.isEmpty && _selectedImageBytes == null) return;

    // Locally add user bubble
    _addUserMessage(text: text, imageBytes: _selectedImageBytes);

    // Actually send to backend
    _sendToBackend(text, _selectedImageBytes);

    // Reset text & image
    setState(() {
      _textCtrl.clear();
      _selectedImageBytes = null;
    });
  }

  void _onSubmitted(String value) => _handleSendText();

  Future<void> _pickFromGallery() async {
    try {
      final xFile = await _picker.pickImage(source: ImageSource.gallery);
      if (xFile != null) {
        final bytes = await xFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint("Gallery pick error: $e");
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final xFile = await _picker.pickImage(source: ImageSource.camera);
      if (xFile != null) {
        final bytes = await xFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint("Camera pick error: $e");
    }
  }

  String _buildConversationMemoryWith(ChatMessage newMessage) {
    const maxMemoryCount = 10;
    final messages = [..._messages, newMessage];

    final recentMessages = messages.length <= maxMemoryCount
        ? messages
        : messages.sublist(messages.length - maxMemoryCount);

    final buffer = StringBuffer();
    for (final msg in recentMessages) {
      final speaker = msg.sender == MessageSender.user ? 'User' : 'AI';
      if (msg.imageBytes != null) {
        buffer.writeln('$speaker: [image attached]');
      }
      if (msg.text.isNotEmpty) {
        buffer.writeln('$speaker: ${msg.text}');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  Future<void> _sendToBackend(String text, Uint8List? imageBytes) async {
    setState(() {
      _isSending = true;
      _aiTyping = true;
    });

    final typingIndex = _messages.length;
    // Add a temporary typing bubble (now with spinning tire).
    _messages.add(ChatMessage(
      sender: MessageSender.ai,
      text: '',
      timeStamp: DateTime.now(),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      // Build conversation memory including the new message
      final simulatedMessage = ChatMessage(
        sender: MessageSender.user,
        text: text,
        imageBytes: imageBytes,
        timeStamp: DateTime.now(),
      );

      final conversationMemory = _buildConversationMemoryWith(simulatedMessage);

      final request = http.MultipartRequest('POST', Uri.parse(kBackendUrl));
      final fullPrompt = '''
        $conversationMemory
        User: ${text.isNotEmpty ? text : '[image only]'}
        AI:
        '''
          .trim();

      request.fields['text'] = fullPrompt;

      if (imageBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'user-upload.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send();
      final resp = await http.Response.fromStream(streamedResponse);

      if (resp.statusCode == 200) {
        String finalText;
        try {
          final decoded = jsonDecode(resp.body);
          finalText = decoded['response'].toString();
        } catch (_) {
          finalText = resp.body;
        }

        setState(() {
          _messages[typingIndex] = ChatMessage(
            sender: MessageSender.ai,
            text: finalText,
            timeStamp: DateTime.now(),
          );
        });
      } else {
        setState(() {
          _messages[typingIndex] = ChatMessage(
            sender: MessageSender.ai,
            text: 'Error: ${resp.statusCode} - ${resp.reasonPhrase}',
            timeStamp: DateTime.now(),
          );
        });
      }
    } catch (e) {
      setState(() {
        _messages[typingIndex] = ChatMessage(
          sender: MessageSender.ai,
          text: "Failed to send: $e",
          timeStamp: DateTime.now(),
        );
      });
    } finally {
      setState(() {
        _isSending = false;
        _aiTyping = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _showImagePreview(Uint8List bytes) {
    setState(() {
      _imagePreviewBytes = bytes;
    });
  }

  void _closeImagePreview() {
    setState(() {
      _imagePreviewBytes = null;
    });
  }

  void _removeSelectedImage() {
    setState(() {
      _selectedImageBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-size wave background
          Positioned.fill(
            child: CustomPaint(
              painter: WavePainter(animation: _waveController),
            ),
          ),

          // Center the chat UI with a max width so it looks better on web
          LayoutBuilder(
            builder: (context, constraints) {
              const double maxWidth = 900;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(constraints.maxWidth, maxWidth),
                  ),
                  child: Column(
                    children: [
                      // Top bar
                      Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: kColorPrimary,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              offset: const Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car, color: Colors.white),
                            const SizedBox(width: 8),
                            const Text(
                              "dash-gem",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _clearChat,
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              tooltip: "Clear Chat",
                            ),
                          ],
                        ),
                      ),

                      // Chat list
                      Expanded(
                        child: Container(
                          color: kColorCream.withOpacity(0.5),
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (_, idx) {
                              final msg = _messages[idx];
                              final isTypingBubble =
                                  (msg.sender == MessageSender.ai &&
                                   msg.text.isEmpty &&
                                   _aiTyping);
                              if (isTypingBubble) {
                                return _TypingBubble(timestamp: msg.timeStamp);
                              } else {
                                return ChatBubble(
                                  chat: msg,
                                  onTapImage: _showImagePreview,
                                  onLongPressBubble: () {
                                    setState(() {
                                      msg.isLiked = !msg.isLiked;
                                    });
                                  },
                                );
                              }
                            },
                          ),
                        ),
                      ),

                      // Bottom bar
                      Container(
                        color: kColorMint.withOpacity(0.2),
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_selectedImageBytes != null)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: Image.memory(
                                      _selectedImageBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _removeSelectedImage,
                                    icon: const Icon(Icons.close),
                                    tooltip: "Remove selected image",
                                  ),
                                ],
                              ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _pickFromGallery,
                                  icon: const Icon(Icons.photo_library_outlined),
                                  tooltip: "Gallery",
                                ),
                                IconButton(
                                  onPressed: _pickFromCamera,
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  tooltip: "Camera",
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black12,
                                          offset: Offset(0, 1),
                                          blurRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: _textCtrl,
                                      onSubmitted: _onSubmitted,
                                      decoration: const InputDecoration(
                                        hintText: 'Type message...',
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _isSending ? null : _handleSendText,
                                  icon: _isSending
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send),
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
            },
          ),

          // Scroll-to-bottom FAB
          if (_showScrollDownBtn)
            Positioned(
              bottom: 70,
              right: 10,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: kColorPrimary.withOpacity(0.8),
                onPressed: _scrollToBottom,
                child: const Icon(Icons.arrow_downward, color: Colors.white),
              ),
            ),

          // Full-screen image preview
          if (_imagePreviewBytes != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeImagePreview,
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Image.memory(_imagePreviewBytes!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ChatBubble: user or AI bubble
// ---------------------------------------------------------------------------
class ChatBubble extends StatelessWidget {
  final ChatMessage chat;
  final VoidCallback onLongPressBubble;
  final Function(Uint8List) onTapImage;

  const ChatBubble({
    Key? key,
    required this.chat,
    required this.onTapImage,
    required this.onLongPressBubble,
  }) : super(key: key);

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = (chat.sender == MessageSender.user);

    if (!isUser) {
      // AI bubble on the left
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: kColorPrimary.withOpacity(0.2),
              child: const Icon(Icons.directions_car, color: Colors.black87),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: GestureDetector(
                onLongPress: onLongPressBubble,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: kColorMint.withOpacity(0.4),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        offset: const Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (chat.imageBytes != null) ...[
                        GestureDetector(
                          onTap: () => onTapImage(chat.imageBytes!),
                          child: Image.memory(chat.imageBytes!, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (chat.text.isNotEmpty)
                        Text(chat.text, style: const TextStyle(color: Colors.black87)),
                      if (chat.isLiked)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              _formatTime(chat.timeStamp),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      );
    } else {
      // User bubble on the right
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTime(chat.timeStamp),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: onLongPressBubble,
              child: Container(
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: kColorLightGreen.withOpacity(0.4),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      offset: const Offset(-1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (chat.imageBytes != null) ...[
                      GestureDetector(
                        onTap: () => onTapImage(chat.imageBytes!),
                        child: Image.memory(chat.imageBytes!, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (chat.text.isNotEmpty)
                      Text(chat.text, style: const TextStyle(color: Colors.black87)),
                    if (chat.isLiked)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: kColorPrimary.withOpacity(0.2),
              child: const Icon(Icons.person, color: Colors.black87),
            ),
          ],
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Typing bubble (show a spinning tire instead of dots)
// ---------------------------------------------------------------------------
class _TypingBubble extends StatelessWidget {
  final DateTime timestamp;
  const _TypingBubble({Key? key, required this.timestamp}) : super(key: key);

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kColorPrimary.withOpacity(0.2),
            child: const Icon(Icons.directions_car, color: Colors.black87),
          ),
          const SizedBox(width: 8),

          // The bubble with our rotating tire
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: kColorMint.withOpacity(0.4),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  offset: const Offset(1, 1),
                  blurRadius: 2,
                ),
              ],
            ),
            // Instead of spinning dots, we use CarTireSpinner
            child: const CarTireSpinner(size: 22),
          ),

          Text(
            _formatTime(timestamp),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A custom spinner that rotates a "tire" icon indefinitely
// ---------------------------------------------------------------------------
class CarTireSpinner extends StatefulWidget {
  final double size;
  const CarTireSpinner({Key? key, this.size = 24}) : super(key: key);

  @override
  State<CarTireSpinner> createState() => _CarTireSpinnerState();
}

class _CarTireSpinnerState extends State<CarTireSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One rotation per 0.8 seconds. Adjust to your liking!
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      // Option A: Use a circle icon to simulate a simple tire
      child: 
        Image.asset('assets/wheel.png',
          width: widget.size,
          height: widget.size
        )
      

      // Option B: If you have an actual tire image in assets (and declared in pubspec.yaml):
      // child: Image.asset(
      //   'assets/tire.png',
      //   width: widget.size,
      //   height: widget.size,
      // ),
    );
  }
}

// ---------------------------------------------------------------------------
// WavePainter with smaller amplitude for the foreground wave
// ---------------------------------------------------------------------------
class WavePainter extends CustomPainter {
  final Animation<double> animation;
  WavePainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Wave #1 (lowest)
    final wavePaint1 = Paint()..color = kColorMint.withOpacity(0.3);
    final wave1 = Path();
    wave1.moveTo(0, h * 0.35);
    for (double x = 0; x <= w; x++) {
      wave1.lineTo(
        x,
        h * 0.35 + math.sin((x + animation.value * 300) * 0.02) * 20,
      );
    }
    wave1.lineTo(w, 0);
    wave1.lineTo(0, 0);
    wave1.close();
    canvas.drawPath(wave1, wavePaint1);

    // Wave #2 (middle)
    final wavePaint2 = Paint()..color = kColorLightGreen.withOpacity(0.4);
    final wave2 = Path();
    wave2.moveTo(0, h * 0.55);
    for (double x = 0; x <= w; x++) {
      wave2.lineTo(
        x,
        h * 0.55 + math.sin((x + animation.value * 400) * 0.015) * 30,
      );
    }
    wave2.lineTo(w, 0);
    wave2.lineTo(0, 0);
    wave2.close();
    canvas.drawPath(wave2, wavePaint2);

    // Wave #3 (closest/highest)
    final wavePaint3 = Paint()..color = kColorMint.withOpacity(0.4);
    final wave3 = Path();
    wave3.moveTo(0, h * 0.75);
    for (double x = 0; x <= w; x++) {
      wave3.lineTo(
        x,
        h * 0.75 + math.sin((x + animation.value * 600) * 0.025) * 40,
      );
    }
    wave3.lineTo(w, h);
    wave3.lineTo(0, h);
    wave3.close();
    canvas.drawPath(wave3, wavePaint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
