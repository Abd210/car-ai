import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
// For animated dots:
import 'package:flutter_spinkit/flutter_spinkit.dart';

/******************************************************************************
 * ENHANCED SINGLE-PAGE FLUTTER CHAT - "dash-gem"
 *
 * Features:
 *   - Custom top bar (car icon + "dash-gem" + clear icon)
 *   - Avatars for AI & user
 *   - Wave background + gradient
 *   - Timestamps
 *   - AI typing indicator with animated dots
 *   - Press Enter to send
 *   - Scroll-to-bottom button (improved logic)
 *   - Tap images to preview in an overlay
 *   - Long-press bubble to "like" a message
 *****************************************************************************/

// Replace with your actual backend endpoint
const String kBackendUrl = 'http://localhost:8080/analyzeDashboardPic';

// Color palette
const Color kColorPrimary = Color(0xFF3D8D7A);
const Color kColorLightGreen = Color(0xFFB3D8A8);
const Color kColorCream = Color(0xFFFBFFE4);
const Color kColorMint = Color(0xFFA3D1C6);

enum MessageSender { user, ai }

class ChatMessage {
  final MessageSender sender;
  final String text;
  final File? imageFile;
  final DateTime timeStamp;
  bool isLiked; // extra feature: user can long-press to "like"

  ChatMessage({
    required this.sender,
    this.text = '',
    this.imageFile,
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
    // Single-page app
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

// ---------------------------------------------------------------------------
// The main single-page chat
// ---------------------------------------------------------------------------
class DashGemChatPage extends StatefulWidget {
  const DashGemChatPage({Key? key}) : super(key: key);

  @override
  State<DashGemChatPage> createState() => _DashGemChatPageState();
}

class _DashGemChatPageState extends State<DashGemChatPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textCtrl = TextEditingController();

  final ScrollController _scrollCtrl = ScrollController();

  late List<ChatMessage> _messages;
  late AnimationController _waveController;

  bool _isSending = false;
  bool _aiTyping = false;
  bool _showScrollDownBtn = false; // show/hide the scroll-down arrow
  File? _imagePreviewFile; // for image overlay preview

  @override
  void initState() {
    super.initState();
    // Animate the wave background
    _waveController =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat();

    // Start with an initial AI greeting
    _messages = [
      ChatMessage(
        sender: MessageSender.ai,
        text: "Hello, how can I help you?",
        timeStamp: DateTime.now(),
      ),
    ];

    // Listen for scroll changes to show/hide the scroll down button
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

  // Called whenever user scrolls
  void _onScrollChanged() {
    // difference between maxScrollExtent & current offset
    final distanceFromBottom =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels;
    // if user is more than 150 px away from bottom, show the button
    bool shouldShow = distanceFromBottom > 150;

    if (shouldShow != _showScrollDownBtn) {
      setState(() {
        _showScrollDownBtn = shouldShow;
      });
    }
  }

  // Clears chat to just the initial greeting
  void _clearChat() {
    setState(() {
      _messages = [
        ChatMessage(
          sender: MessageSender.ai,
          text: "Hello, how can I help you?",
          timeStamp: DateTime.now(),
        ),
      ];
    });
    // Jump to bottom after clearing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  // Smoothly scroll to the bottom
  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // Adds a user message
  void _addUserMessage({String text = '', File? imageFile}) {
    setState(() {
      _messages.add(ChatMessage(
        sender: MessageSender.user,
        text: text,
        imageFile: imageFile,
        timeStamp: DateTime.now(),
      ));
    });

    // After building, scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  // Adds an AI message
  void _addAIMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        sender: MessageSender.ai,
        text: text,
        timeStamp: DateTime.now(),
      ));
    });

    // After building, scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  // If user picks from gallery
  Future<void> _pickFromGallery() async {
    try {
      final xFile = await _picker.pickImage(source: ImageSource.gallery);
      if (xFile != null) {
        final file = File(xFile.path);
        _addUserMessage(imageFile: file);
        _sendToBackend('', file);
      }
    } catch (e) {
      debugPrint("Gallery pick error: $e");
    }
  }

  // If user picks from camera
  Future<void> _pickFromCamera() async {
    try {
      // On web, fallback if no camera or not served on https/localhost
      final xFile = await _picker.pickImage(source: ImageSource.camera);
      if (xFile != null) {
        final file = File(xFile.path);
        _addUserMessage(imageFile: file);
        _sendToBackend('', file);
      }
    } catch (e) {
      debugPrint("Camera pick error: $e");
    }
  }

  // Called when user hits Send or presses Enter
  void _handleSendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _addUserMessage(text: text);
    _textCtrl.clear();
    _sendToBackend(text, null);
  }

  // Called when user presses Enter
  void _onSubmitted(String value) {
    _handleSendText();
  }

  // Actually send data to backend
  Future<void> _sendToBackend(String text, File? imageFile) async {
    setState(() {
      _isSending = true;
      _aiTyping = true;
    });

    // Insert an AI typing bubble (with animated dots)
    final typingIndex = _messages.length;
    _messages.add(ChatMessage(
      sender: MessageSender.ai,
      text: "",
      timeStamp: DateTime.now(),
    ));

    // Jump to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(kBackendUrl));

      if (imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'car.jpg',
        ));
      }
      request.fields['text'] =
          text.isNotEmpty ? text : "Analyze my car dashboard.";

      final streamedResp = await request.send();
      final resp = await http.Response.fromStream(streamedResp);

      if (resp.statusCode == 200) {
        setState(() {
          // Replace the typing bubble text with actual AI message
          _messages[typingIndex] = ChatMessage(
            sender: MessageSender.ai,
            text: resp.body,
            timeStamp: DateTime.now(),
          );
        });
      } else {
        setState(() {
          _messages[typingIndex] = ChatMessage(
            sender: MessageSender.ai,
            text: "Error: ${resp.statusCode} - ${resp.reasonPhrase}",
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
      // Scroll to bottom after AI responds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  // Show an overlay preview of an image
  void _showImagePreview(File file) {
    setState(() {
      _imagePreviewFile = file;
    });
  }

  // Hide the image preview overlay
  void _closeImagePreview() {
    setState(() {
      _imagePreviewFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // main body
      body: Stack(
        children: [
          // Wave background with gradient
          CustomPaint(
            painter: WavePainter(animation: _waveController),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, kColorCream],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          // Column with top bar, list, input
          Column(
            children: [
              // Custom top bar
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
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, idx) {
                    // If AI bubble is in "typing" state (no text), show animated dots
                    final msg = _messages[idx];
                    final isTypingIndicator =
                        (msg.sender == MessageSender.ai &&
                         msg.text.isEmpty &&
                         _aiTyping);

                    if (isTypingIndicator) {
                      return _TypingBubble(timestamp: msg.timeStamp);
                    } else {
                      return ChatBubble(
                        chat: msg,
                        onTapImage: _showImagePreview,
                        onLongPressBubble: () {
                          // Toggle 'like'
                          setState(() {
                            msg.isLiked = !msg.isLiked;
                          });
                        },
                      );
                    }
                  },
                ),
              ),

              // Bottom input bar
              Container(
                color: kColorMint.withOpacity(0.2),
                padding: const EdgeInsets.all(4),
                child: Row(
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
                          decoration: const InputDecoration(
                            hintText: "Type message...",
                            border: InputBorder.none,
                          ),
                          onSubmitted: _onSubmitted,
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
              ),
            ],
          ),

          // Scroll-to-bottom button if user is scrolled up
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

          // Image preview overlay
          if (_imagePreviewFile != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeImagePreview,
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Image.file(_imagePreviewFile!),
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
// ChatBubble with Avatars, Timestamps, optional 'like' heart
// ---------------------------------------------------------------------------
class ChatBubble extends StatelessWidget {
  final ChatMessage chat;
  final VoidCallback onLongPressBubble;
  final Function(File) onTapImage;
  const ChatBubble({
    Key? key,
    required this.chat,
    required this.onLongPressBubble,
    required this.onTapImage,
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
      // AI bubble (left)
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
                  constraints: const BoxConstraints(maxWidth: 240),
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
                      if (chat.imageFile != null) ...[
                        GestureDetector(
                          onTap: () => onTapImage(chat.imageFile!),
                          child: Image.file(chat.imageFile!, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (chat.text.isNotEmpty)
                        Text(
                          chat.text,
                          style: const TextStyle(color: Colors.black87),
                        ),
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
      // User bubble (right)
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
                constraints: const BoxConstraints(maxWidth: 240),
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
                    if (chat.imageFile != null) ...[
                      GestureDetector(
                        onTap: () => onTapImage(chat.imageFile!),
                        child: Image.file(chat.imageFile!, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (chat.text.isNotEmpty)
                      Text(
                        chat.text,
                        style: const TextStyle(color: Colors.black87),
                      ),
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
// _TypingBubble: An AI bubble that shows an animated typing indicator
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
          // AI avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: kColorPrimary.withOpacity(0.2),
            child: const Icon(Icons.directions_car, color: Colors.black87),
          ),
          const SizedBox(width: 8),
          // BUBBLE with animated dots
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            constraints: const BoxConstraints(maxWidth: 240),
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
            child: SpinKitThreeBounce(
              color: Colors.black87,
              size: 15,
            ),
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
// WavePainter with slight gradient behind it
// ---------------------------------------------------------------------------
class WavePainter extends CustomPainter {
  final Animation<double> animation;
  WavePainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // We'll rely on the parent Container's gradient fill as the base.
    // Then draw two waves on top.
    final wavePaint1 = Paint()..color = kColorMint.withOpacity(0.4);
    final wave1 = Path();
    wave1.moveTo(0, h * 0.3);
    for (double x = 0; x <= w; x++) {
      wave1.lineTo(
        x,
        h * 0.3 + math.sin((x + animation.value * 600) * 0.01) * 25,
      );
    }
    wave1.lineTo(w, 0);
    wave1.lineTo(0, 0);
    wave1.close();
    canvas.drawPath(wave1, wavePaint1);

    final wavePaint2 = Paint()..color = kColorLightGreen.withOpacity(0.4);
    final wave2 = Path();
    wave2.moveTo(0, h * 0.45);
    for (double x = 0; x <= w; x++) {
      wave2.lineTo(
        x,
        h * 0.45 + math.sin((x + animation.value * 700) * 0.02) * 30,
      );
    }
    wave2.lineTo(w, 0);
    wave2.lineTo(0, 0);
    wave2.close();
    canvas.drawPath(wave2, wavePaint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
// fair game