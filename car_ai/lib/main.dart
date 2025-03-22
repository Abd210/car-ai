import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http_parser/http_parser.dart'; // Needed for MediaType
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

// ---------------------------------------------------------------------------
// Where we send the request
// ---------------------------------------------------------------------------
const String kBackendUrl =
    'https://dash-gem-ef3cd0583e98.herokuapp.com/analyzeDashboardPic';

// Some colors for the wave background:
const Color kColorPrimary = Color(0xFF3D8D7A);
const Color kColorLightGreen = Color(0xFFB3D8A8);
const Color kColorCream = Color(0xFFFBFFE4);
const Color kColorMint = Color(0xFFA3D1C6);

// Who sent the message
enum MessageSender { user, ai }

// Chat message model
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

// ---------------------------------------------------------------------------
// Main chat page
// ---------------------------------------------------------------------------
class DashGemChatPage extends StatefulWidget {
  const DashGemChatPage({Key? key}) : super(key: key);

  @override
  State<DashGemChatPage> createState() => _DashGemChatPageState();
}

class _DashGemChatPageState extends State<DashGemChatPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollCtrl = ScrollController();

  // Simple textfield controller
  final TextEditingController _textCtrl = TextEditingController();

  // Animation controller for wave
  late AnimationController _waveController;

  // Chat messages
  List<ChatMessage> _messages = [];

  // UI states
  bool _isSending = false;  
  bool _aiTyping = false;  
  bool _showScrollDownBtn = false;

  // If user chooses an image but hasn't sent yet, store it here
  Uint8List? _selectedImageBytes;

  // Full-screen preview of any image (when tapped in chat)
  Uint8List? _imagePreviewBytes;

  @override
  void initState() {
    super.initState();
    // Start wave animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Example "Welcome" message
    _messages = [
      ChatMessage(
        sender: MessageSender.ai,
        text: "Hello, how can I help you?",
        timeStamp: DateTime.now(),
      ),
    ];

    // Listen for scrolling
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

  // Show/hide "scroll to bottom" button
  void _onScrollChanged() {
    final distanceFromBottom = _scrollCtrl.position.maxScrollExtent
        - _scrollCtrl.position.pixels;
    bool shouldShow = distanceFromBottom > 150;
    if (shouldShow != _showScrollDownBtn) {
      setState(() {
        _showScrollDownBtn = shouldShow;
      });
    }
  }

  // Clears chat
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

  // Scroll to bottom
  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // Build the conversation memory to send to backend
  String _buildConversationMemory() {
    // Example format: "User: Hello\nAI: How can I help?\nUser: I need help!\n..."
    final buffer = StringBuffer();
    for (final msg in _messages) {
      final speaker = (msg.sender == MessageSender.user) ? 'User' : 'AI';
      // Combine both text & possible images info (basic). You can customize more if needed
      if (msg.imageBytes != null) {
        buffer.writeln('$speaker: [image attached]');
      }
      if (msg.text.isNotEmpty) {
        buffer.writeln('$speaker: ${msg.text}');
      }
      buffer.writeln(); // blank line
    }
    return buffer.toString().trim();
  }

  // Add user message
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

  // Add AI message
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

  // On user pressing Enter or clicking Send
  void _handleSendText() {
    final text = _textCtrl.text.trim();
    // If user typed nothing AND didn't pick an image, do nothing
    if (text.isEmpty && _selectedImageBytes == null) return;

    // Locally add user's chat bubble (which might have text, image, or both)
    _addUserMessage(text: text, imageBytes: _selectedImageBytes);

    // Check how many words user typed (simple check by splitting on spaces)
    final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    // Send 1 request if < 20 words, or 2 requests if >= 20 words
    _sendToBackend(text, _selectedImageBytes, isFollowUp: false).then((_) async {
      // If user typed a big message, do a follow-up request
      if (wordCount >= 20) {
        await _sendToBackend(
          "Follow-up: The user wrote a lengthy message. Please provide more details.",
          null,
          isFollowUp: true,
        );
      }
    });

    // Clear local states
    setState(() {
      _textCtrl.clear();
      _selectedImageBytes = null;
    });
  }

  // On textfield submission
  void _onSubmitted(String value) {
    _handleSendText();
  }

  // Pick from gallery (but *don't* send yet; wait for user to press Send)
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

  // Pick from camera (but *don't* send yet; wait for user to press Send)
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

  // *** The crucial method that does the "curl-like" request. ***
  // If `isFollowUp` is true, we label the text differently in the request.
  Future<void> _sendToBackend(String text, Uint8List? imageBytes,
      {required bool isFollowUp}) async {
    setState(() {
      _isSending = true;
      _aiTyping = true; // We'll show a typing bubble
    });

    // Insert a temporary AI "typing" bubble at the end
    final typingIndex = _messages.length;
    _messages.add(ChatMessage(
      sender: MessageSender.ai,
      text: '',
      timeStamp: DateTime.now(),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(kBackendUrl));

      // Add the entire conversation so far
      final conversationMemory = _buildConversationMemory();
      request.fields['memory'] = conversationMemory;

      // Add text field
      // If this is a follow-up, we prefix it in some way to differentiate
      if (isFollowUp) {
        request.fields['text'] = "FOLLOW-UP >> $text";
      } else {
        request.fields['text'] = text.isNotEmpty ? text : 'User posted only an image.';
      }

      // Add file under field name "image"
      if (imageBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'user-upload.jpg',
            contentType: MediaType('image', 'jpeg'), // or 'png' if needed
          ),
        );
      }

      // Send
      final streamedResponse = await request.send();
      final resp = await http.Response.fromStream(streamedResponse);

      if (resp.statusCode == 200) {
        // Attempt to decode as JSON
        String finalText;
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded.containsKey('response')) {
            finalText = decoded['response'].toString();
          } else {
            finalText = resp.body;
          }
        } catch (_) {
          finalText = resp.body;
        }

        // Replace "typing bubble" with final AI text
        setState(() {
          _messages[typingIndex] = ChatMessage(
            sender: MessageSender.ai,
            text: finalText,
            timeStamp: DateTime.now(),
          );
        });
      } else {
        // Replace "typing bubble" with error
        setState(() {
          _messages[typingIndex] = ChatMessage(
            sender: MessageSender.ai,
            text: 'Error: ${resp.statusCode} - ${resp.reasonPhrase}',
            timeStamp: DateTime.now(),
          );
        });
      }
    } catch (e) {
      // Replace "typing bubble" with exception
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

  // Show an overlay of the image
  void _showImagePreview(Uint8List bytes) {
    setState(() {
      _imagePreviewBytes = bytes;
    });
  }

  // Close preview
  void _closeImagePreview() {
    setState(() {
      _imagePreviewBytes = null;
    });
  }

  // Remove the "selected" image (if user picks one but wants to unselect)
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
          // Painted wave background (3 layers for bigger effect)
          CustomPaint(
            painter: WavePainter(animation: _waveController),
            child: Container(),
          ),

          Column(
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
                      // Show typing bubble
                      return _TypingBubble(timestamp: msg.timeStamp);
                    } else {
                      // Show normal chat bubble
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

              // Bottom bar
              Container(
                color: kColorMint.withOpacity(0.2),
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // If user has selected an image (but not sent yet), show a tiny preview + remove button
                    if (_selectedImageBytes != null)
                      Row(
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
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

          // Scroll to bottom button
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

          // Image preview
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
      // AI bubble (left)
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
                      if (chat.imageBytes != null) ...[
                        GestureDetector(
                          onTap: () => onTapImage(chat.imageBytes!),
                          child: Image.memory(chat.imageBytes!, fit: BoxFit.cover),
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
                          child: Icon(Icons.favorite,
                              size: 16, color: Colors.redAccent),
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
                    if (chat.imageBytes != null) ...[
                      GestureDetector(
                        onTap: () => onTapImage(chat.imageBytes!),
                        child: Image.memory(chat.imageBytes!, fit: BoxFit.cover),
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
                        child: Icon(Icons.favorite,
                            size: 16, color: Colors.redAccent),
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
// Typing bubble
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
            child: const SpinKitThreeBounce(
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
// WavePainter for the background (3 waves, bigger amplitude)
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
        h * 0.35 + math.sin((x + animation.value * 300) * 0.02) * 40,
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
        h * 0.55 + math.sin((x + animation.value * 400) * 0.015) * 60,
      );
    }
    wave2.lineTo(w, 0);
    wave2.lineTo(0, 0);
    wave2.close();
    canvas.drawPath(wave2, wavePaint2);

    // Wave #3 (highest)
    final wavePaint3 = Paint()..color = kColorMint.withOpacity(0.4);
    final wave3 = Path();
    wave3.moveTo(0, h * 0.75);
    for (double x = 0; x <= w; x++) {
      wave3.lineTo(
        x,
        h * 0.75 + math.sin((x + animation.value * 600) * 0.025) * 80,
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
