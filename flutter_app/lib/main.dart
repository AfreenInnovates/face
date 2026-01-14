import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

// --- GLOBAL SESSION ID ---
final String appSessionId = DateTime.now().millisecondsSinceEpoch.toString();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  final cameras = await availableCameras();
  
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emotion Lens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
      ),
      home: MainNavigation(cameras: cameras),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const MainNavigation({super.key, required this.cameras});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  String? _detectedEmotion;
  bool _hasDetectedEmotion = false;

  void _onEmotionDetected(String emotion) {
    setState(() {
      _detectedEmotion = emotion;
      _hasDetectedEmotion = true;
      _currentIndex = 2; // Navigate to chat
    });
  }

  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Pass the navigation callback to LandingPage
          LandingPage(
            cameras: widget.cameras, 
            onStartDetection: () => _onTabChange(1), 
          ),
          CameraPage(
            key: const ValueKey('camera_page'),
            cameras: widget.cameras,
            onEmotionDetected: _onEmotionDetected,
          ),
          ChatPage(emotion: _detectedEmotion ?? 'neutral'),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a1d3a),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.home, 'Home', 0),
                _buildNavItem(Icons.camera_alt, 'Detect', 1),
                _buildNavItem(Icons.chat_bubble, 'Chat', 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabChange(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4D96FF).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF4D96FF) : Colors.white60,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF4D96FF) : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LandingPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final VoidCallback onStartDetection; // Added Callback
  
  const LandingPage({super.key, required this.cameras, required this.onStartDetection});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _floatController;
  late AnimationController _rotateController;
  bool _isLoading = true;
  
  final List<Emotion> _emotions = [
    Emotion('😊', 'Happy', const Color(0xFFFFD93D)),
    Emotion('😢', 'Sad', const Color(0xFF6BCB77)),
    Emotion('😠', 'Angry', const Color(0xFFFF6B6B)),
    Emotion('😮', 'Surprised', const Color(0xFF4D96FF)),
    Emotion('😐', 'Neutral', const Color(0xFF9D84B7)),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat(reverse: true);
    _floatController = AnimationController(duration: const Duration(milliseconds: 3000), vsync: this)..repeat(reverse: true);
    _rotateController = AnimationController(duration: const Duration(milliseconds: 20000), vsync: this)..repeat();
    
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    // Request permission first
    final status = await Permission.camera.request();
    if (status.isGranted) {
      // Execute the callback to switch tabs
      widget.onStartDetection();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera access is required'), backgroundColor: Color(0xFFFF6B6B)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBackground(rotateController: _rotateController),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                child: _isLoading ? _buildLoadingScreen() : _buildMainScreen(MediaQuery.of(context).size),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      key: const ValueKey('loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Transform.scale(
              scale: 1.0 + (_pulseController.value * 0.1),
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFF4D96FF).withOpacity(0.6), const Color(0xFF4D96FF).withOpacity(0.2)])),
                child: const Center(child: Text('🎭', style: TextStyle(fontSize: 60))),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Initializing...', style: TextStyle(fontSize: 18, color: Colors.white70, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildMainScreen(Size size) {
    return Column(
      key: const ValueKey('main'),
      children: [
        const SizedBox(height: 40),
        Column(
          children: [
            const Text('EMOTION', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 8, height: 1)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('LENS', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 8)),
              const SizedBox(width: 12),
              Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF4D96FF), Color(0xFFFFD93D)]))),
            ]),
            const SizedBox(height: 8),
            const Text('AI-Powered Emotion Recognition', style: TextStyle(fontSize: 14, color: Colors.white38, letterSpacing: 1.5)),
          ],
        ),
        const Spacer(),
        AnimatedBuilder(
          animation: _floatController,
          builder: (context, child) => Transform.translate(offset: Offset(0, math.sin(_floatController.value * math.pi * 2) * 15), child: _buildEmotionCircle()),
        ),
        const Spacer(),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Experience real-time emotion detection powered by advanced neural networks', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white60, height: 1.5))),
        const SizedBox(height: 48),
        GestureDetector(
          onTap: _handleStart, // Call the new handler
          child: Container(
            width: double.infinity, height: 64,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4D96FF), Color(0xFF6BCB77)]), borderRadius: BorderRadius.circular(32)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt_outlined, color: Colors.white, size: 24), SizedBox(width: 12), Text('Start Detection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white))]),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildEmotionCircle() {
    return SizedBox(
      width: 280, height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 280, height: 280, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFF4D96FF).withOpacity(0.15), Colors.transparent]))),
          ...List.generate(_emotions.length, (index) {
            final angle = (index * 2 * math.pi / _emotions.length) - math.pi / 2;
            final radius = 100.0;
            return AnimatedBuilder(
              animation: _rotateController,
              builder: (context, child) {
                final currentAngle = angle + (_rotateController.value * 2 * math.pi);
                return Transform.translate(
                  offset: Offset(math.cos(currentAngle) * radius, math.sin(currentAngle) * radius),
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _emotions[index].color.withOpacity(0.2), border: Border.all(color: _emotions[index].color.withOpacity(0.3), width: 2)),
                    child: Center(child: Text(_emotions[index].emoji, style: const TextStyle(fontSize: 28))),
                  ),
                );
              },
            );
          }),
          Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFF4D96FF).withOpacity(0.3), const Color(0xFF4D96FF).withOpacity(0.1)]), border: Border.all(color: const Color(0xFF4D96FF).withOpacity(0.5), width: 2)), child: const Center(child: Text('🎭', style: TextStyle(fontSize: 40)))),
        ],
      ),
    );
  }
}

class AnimatedBackground extends StatelessWidget {
  final AnimationController rotateController;
  const AnimatedBackground({super.key, required this.rotateController});
  @override
  Widget build(BuildContext context) {
    return Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0A0E27), Color(0xFF1a1d3a), Color(0xFF0A0E27)])));
  }
}

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(String)? onEmotionDetected;
  const CameraPage({super.key, required this.cameras, this.onEmotionDetected});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isInitialized = false;
  String _currentEmotion = 'Scanning...';
  double _emotionProbability = 0.0;
  Color _emotionColor = const Color(0xFF9D84B7);
  Timer? _detectionTimer;
  final String _apiUrl = 'http://localhost:5000/detect_emotion';
  
  late AnimationController _scanController;
  late AnimationController _pulseController;
  bool _faceDetected = false;
  String? _trackedEmotion;
  DateTime? _emotionStartTime;
  bool _emotionFinalized = false;
  Timer? _emotionTrackingTimer;
  
  final Map<String, EmotionData> _emotionMap = {
    'happy': EmotionData('😊', 'Happy', const Color(0xFFFFD93D)),
    'sad': EmotionData('😢', 'Sad', const Color(0xFF6BCB77)),
    'angry': EmotionData('😠', 'Angry', const Color(0xFFFF6B6B)),
    'surprise': EmotionData('😮', 'Surprised', const Color(0xFF4D96FF)),
    'fear': EmotionData('😨', 'Fearful', const Color(0xFF9D84B7)),
    'disgust': EmotionData('😖', 'Disgusted', const Color(0xFFFF8C42)),
    'neutral': EmotionData('😐', 'Neutral', const Color(0xFF95A3B3)),
  };

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat();
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    CameraDescription camera = widget.cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => widget.cameras[0]);
    _controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _startDetection();
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  bool _isCapturing = false;
  void _startDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_controller != null && _controller!.value.isInitialized && !_isCapturing) _detectEmotion();
    });
  }

  Future<void> _detectEmotion() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing || _emotionFinalized) return;
    _isCapturing = true;
    try {
      final XFile image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      final response = await http.post(Uri.parse(_apiUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'image': 'data:image/jpeg;base64,$base64Image', 'session_id': appSessionId})).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['faces'] != null && data['faces'].isNotEmpty) {
          final face = data['faces'][0];
          final emotionKey = face['emotion'].toString().toLowerCase();
          final emotionData = _emotionMap[emotionKey] ?? EmotionData('🎭', emotionKey, const Color(0xFF95A3B3));
          
          if (mounted) {
            setState(() {
              _faceDetected = true;
              _currentEmotion = emotionData.name;
              _emotionProbability = face['probability'];
              _emotionColor = emotionData.color;
              
              if (_trackedEmotion != emotionKey) {
                _trackedEmotion = emotionKey;
                _emotionStartTime = DateTime.now();
                _emotionFinalized = false;
              } else if (_emotionStartTime != null && !_emotionFinalized) {
                if (DateTime.now().difference(_emotionStartTime!).inSeconds >= 5) {
                  _emotionFinalized = true;
                  _detectionTimer?.cancel();
                  _controller?.dispose();
                  _controller = null;
                  
                  // Wait for the UI "Captured!" screen to show, then navigate
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (widget.onEmotionDetected != null && mounted) widget.onEmotionDetected!(emotionKey);
                  });
                }
              }
            });
          }
        }
      }
    } catch (e) {
      print('Detection error: $e');
    } finally {
      _isCapturing = false;
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _emotionTrackingTimer?.cancel();
    _controller?.dispose();
    _scanController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_emotionFinalized) return Scaffold(backgroundColor: const Color(0xFF0A0E27), body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 80, color: _emotionColor), const SizedBox(height: 24), Text('Emotion Captured!', style: TextStyle(color: _emotionColor, fontSize: 24, fontWeight: FontWeight.w700))])));
    if (!_isInitialized || _controller == null) return const Scaffold(backgroundColor: Color(0xFF0A0E27), body: Center(child: CircularProgressIndicator()));

    final emotionData = _emotionMap[_currentEmotion.toLowerCase()];
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Center(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: CameraPreview(_controller!)))),
          if (!_faceDetected) Positioned.fill(child: AnimatedBuilder(animation: _scanController, builder: (_, __) => CustomPaint(painter: ScanLinePainter(progress: _scanController.value, color: const Color(0xFF4D96FF))))),
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(24), border: Border.all(color: _emotionColor.withOpacity(0.5), width: 2), boxShadow: [BoxShadow(color: _emotionColor.withOpacity(0.3), blurRadius: 20)]),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [if (emotionData != null) Text(emotionData.emoji, style: const TextStyle(fontSize: 36)), const SizedBox(width: 16), Text(_currentEmotion.toUpperCase(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _emotionColor))]),
                        if (_faceDetected) ...[const SizedBox(height: 16), Text('CONFIDENCE: ${(_emotionProbability * 100).toStringAsFixed(0)}%', style: TextStyle(color: _emotionColor, fontWeight: FontWeight.bold))],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;
  ScanLinePainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = color.withOpacity(0.6)..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class Emotion {
  final String emoji;
  final String name;
  final Color color;
  Emotion(this.emoji, this.name, this.color);
}

class EmotionData {
  final String emoji;
  final String name;
  final Color color;
  EmotionData(this.emoji, this.name, this.color);
}

class ChatPage extends StatefulWidget {
  final String emotion;
  const ChatPage({super.key, required this.emotion});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isListening = false;
  bool _isLoading = false;
  bool _isTtsEnabled = true;
  final String _apiUrl = 'http://localhost:5000/chat';
  late AnimationController _pulseController;
  
  final Map<String, EmotionData> _emotionMap = {
    'happy': EmotionData('😊', 'Happy', const Color(0xFFFFD93D)),
    'sad': EmotionData('😢', 'Sad', const Color(0xFF6BCB77)),
    'angry': EmotionData('😠', 'Angry', const Color(0xFFFF6B6B)),
    'surprise': EmotionData('😮', 'Surprised', const Color(0xFF4D96FF)),
    'fear': EmotionData('😨', 'Fearful', const Color(0xFF9D84B7)),
    'disgust': EmotionData('😖', 'Disgusted', const Color(0xFFFF8C42)),
    'neutral': EmotionData('😐', 'Neutral', const Color(0xFF95A3B3)),
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this)..repeat(reverse: true);
    _initializeSpeech();
    _initializeTts();
    
    // --- INSTANT START ---
    // We send the message as soon as the UI Frame is ready.
    // We trust 'widget.emotion' because CameraPage won't navigate here unless it's confirmed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _sendMessage('Hello!', isInitial: true);
    });
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.7);
  }

  Future<void> _initializeSpeech() async {
    await _speech.initialize();
  }

  void _startListening() async {
    if (await Permission.microphone.request().isGranted) {
      await _flutterTts.stop();
      
      setState(() => _isListening = true);
      
      await _speech.listen(
        onResult: (result) {
          setState(() => _textController.text = result.recognizedWords);
          
          // --- AUTO SEND LOGIC ---
          if (result.finalResult) {
            _stopListening();
            if (result.recognizedWords.isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 300), () {
                _sendMessage(result.recognizedWords);
              });
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2), // Auto-stop after silence
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _sendMessage(String message, {bool isInitial = false}) async {
    if (message.trim().isEmpty && !isInitial) return;
    await _flutterTts.stop();

    setState(() {
      if (!isInitial) {
        _messages.add({'role': 'user', 'content': message});
        _textController.clear();
      }
      _isLoading = true;
    });

    try {
      final history = _messages.map((msg) => {'role': msg['role'] ?? 'user', 'content': msg['content'] ?? ''}).toList();
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'emotion': widget.emotion, // Confirmed emotion
          'message': isInitial ? 'Hello, I\'m feeling ${widget.emotion}. Can you help me?' : message,
          'history': history,
          'session_id': appSessionId, 
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assistantMessage = data['message'] as String;
        setState(() => _messages.add({'role': 'assistant', 'content': assistantMessage}));
        if (_isTtsEnabled) await _flutterTts.speak(assistantMessage);
      }
    } catch (e) {
      print('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _flutterTts.stop();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emotionData = _emotionMap[widget.emotion.toLowerCase()] ?? EmotionData('😐', 'Neutral', const Color(0xFF95A3B3));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(children: [Text(emotionData.emoji, style: const TextStyle(fontSize: 24)), const SizedBox(width: 12), Text('Emotion Chat', style: TextStyle(color: emotionData.color, fontWeight: FontWeight.w700))]),
        actions: [IconButton(onPressed: () => setState(() { _isTtsEnabled = !_isTtsEnabled; if(!_isTtsEnabled) _flutterTts.stop(); }), icon: Icon(_isTtsEnabled ? Icons.volume_up : Icons.volume_off, color: _isTtsEnabled ? emotionData.color : Colors.white54))],
      ),
      body: Column(
        children: [
          // 1. Emotion Indicator (Restored)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: emotionData.color.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: emotionData.color.withOpacity(0.3))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('Detected Emotion: ', style: TextStyle(color: Colors.white70, fontSize: 14)), Text(emotionData.name.toUpperCase(), style: TextStyle(color: emotionData.color, fontSize: 16, fontWeight: FontWeight.w700))]),
          ),
          
          // 2. Chat List (Restored)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: isUser ? const Color(0xFF4D96FF).withOpacity(0.2) : const Color(0xFF1a1d3a), borderRadius: BorderRadius.circular(20), border: Border.all(color: isUser ? const Color(0xFF4D96FF).withOpacity(0.3) : Colors.white.withOpacity(0.1))),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    child: Text(message['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) Container(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(emotionData.color))), const SizedBox(width: 12), const Text('Thinking...', style: TextStyle(color: Colors.white60))])),
          
          // 3. Fancy Input Area (Restored)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1a1d3a), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -2))]),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _isLoading ? null : (_isListening ? _stopListening : _startListening),
                  child: AnimatedBuilder(
                    animation: _isListening ? _pulseController : const AlwaysStoppedAnimation(0),
                    builder: (context, child) => Transform.scale(scale: _isListening ? 1.0 + (_pulseController.value * 0.1) : 1.0, child: Container(width: 48, height: 48, decoration: BoxDecoration(color: _isListening ? const Color(0xFFFF6B6B).withOpacity(0.3) : const Color(0xFF4D96FF).withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: _isListening ? const Color(0xFFFF6B6B) : const Color(0xFF4D96FF), width: 2)), child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? const Color(0xFFFF6B6B) : const Color(0xFF4D96FF)))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: _isListening ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.2))),
                    child: TextField(
                      controller: _textController,
                      enabled: !_isListening && !_isLoading,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(hintText: _isListening ? 'Listening...' : 'Type or speak...', hintStyle: TextStyle(color: _isListening ? const Color(0xFFFF6B6B) : Colors.white54), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                      onSubmitted: (text) { if (text.trim().isNotEmpty && !_isLoading) _sendMessage(text); },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () { if (_textController.text.trim().isNotEmpty && !_isLoading && !_isListening) _sendMessage(_textController.text); },
                  child: Container(width: 48, height: 48, decoration: BoxDecoration(color: emotionData.color.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: emotionData.color, width: 2)), child: Icon(Icons.send, color: emotionData.color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}