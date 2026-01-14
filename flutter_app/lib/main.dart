import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui'; // For BackdropFilter

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

// --- GLOBAL SESSION ID ---
final String appSessionId = DateTime.now().millisecondsSinceEpoch.toString();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Edge-to-Edge System UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
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
    // Android Expressive 3 Seed Color
    const seedColor = Color(0xFF104A8E); // Strong Sapphire
    
    return MaterialApp(
      title: 'Emotion Lens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
        textTheme: GoogleFonts.outfitTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFFDF7FF), // Surface
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 80,
          indicatorColor: ColorScheme.fromSeed(seedColor: seedColor).secondaryContainer,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
           dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: const Color(0xFF141218), // Dark Surface
         navigationBarTheme: NavigationBarThemeData(
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 80,
          indicatorColor: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark).secondaryContainer,
        ),
      ),
      themeMode: ThemeMode.system, // Respect system mode
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
  
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Logic to switch tabs
  void _onEmotionDetected(String emotion) {
    setState(() {
      _detectedEmotion = emotion;
      _onTabChange(2);
    });
  }

  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutQuart,
    );
  }

  @override
  Widget build(BuildContext context) {
    // final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        physics: const NeverScrollableScrollPhysics(), // Disable swipe to change page, forcing use of bottom nav
        children: [
          LandingPage(
            cameras: widget.cameras, 
            onStartDetection: () => _onTabChange(1), 
          ),
          CameraPage(
            cameras: widget.cameras,
            onEmotionDetected: _onEmotionDetected,
            isActive: _currentIndex == 1,
          ),
          ChatPage(emotion: _detectedEmotion ?? 'neutral'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChange,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Detect',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LANDING PAGE - Expressive & Bold
// ---------------------------------------------------------------------------
class LandingPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final VoidCallback onStartDetection;
  
  const LandingPage({super.key, required this.cameras, required this.onStartDetection});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  late AnimationController _doodleController;
  late AnimationController _bgController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _doodleController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    
    final entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnimation = CurvedAnimation(parent: entryController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: entryController, curve: Curves.easeOutQuad));
    
    entryController.forward();
  }

  @override
  void dispose() {
    _doodleController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      widget.onStartDetection();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera access is required'), 
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
          )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      body: Stack(
        children: [
          // Dynamic Background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return CustomPaint(
                  painter: AnimatedBackgroundPainter(
                    color1: colorScheme.primaryContainer,
                    color2: colorScheme.surface,
                    animationValue: _bgController.value,
                  ),
                );
              },
            ),
          ),
          
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      // Expressive Big Text
                      Text(
                        'Emotion\nLens',
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          color: colorScheme.onSurface,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Real-time AI recognition\nthat understands you.',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const Spacer(),
                      
                      // Doodle Visualization
                      Center(
                        child: SizedBox(
                          height: 300,
                          width: 300,
                          child: AnimatedBuilder(
                            animation: _doodleController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: DoodlePainter(
                                  color: colorScheme.primary,
                                  animationValue: _doodleController.value,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      
                      const Spacer(flex: 2),
                      
                      // Big CTA Button
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: FilledButton.icon(
                          onPressed: _handleStart,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 4,
                            shadowColor: colorScheme.primary.withOpacity(0.4),
                          ),
                          icon: const Icon(Icons.camera_rounded, size: 28),
                          label: Text('Start Detection', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
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

// ---------------------------------------------------------------------------
// CAMERA PAGE - Minimal & Focused
// ---------------------------------------------------------------------------
class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(String)? onEmotionDetected;
  final bool isActive;
  
  const CameraPage({super.key, required this.cameras, this.onEmotionDetected, required this.isActive});
  
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  bool _isInitialized = false;
  String _currentEmotion = 'Scanning...';
  double _emotionProbability = 0.0;
  Timer? _detectionTimer;
  final String _apiUrl = 'http://localhost:5000/detect_emotion';
  
  bool _faceDetected = false;
  String? _trackedEmotion;
  DateTime? _emotionStartTime;
  bool _emotionFinalized = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initializeCamera();
    }
  }

  @override
  void didUpdateWidget(CameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initializeCamera();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;
    final camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front, 
      orElse: () => widget.cameras.first
    );
    
    _controller = CameraController(
      camera, 
      ResolutionPreset.medium, 
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _startDetection();
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _stopCamera({bool fromDispose = false}) {
    _detectionTimer?.cancel();
    _controller?.dispose();
    _controller = null;
    if (mounted && !fromDispose) setState(() => _isInitialized = false);
  }

  bool _isCapturing = false;
  void _startDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_controller != null && _controller!.value.isInitialized && !_isCapturing) {
        _detectEmotion();
      }
    });
  }

  Future<void> _detectEmotion() async {
    if (_controller == null || _isCapturing || _emotionFinalized) return;
    _isCapturing = true;
    
    try {
      final XFile image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final response = await http.post(
        Uri.parse(_apiUrl), 
        headers: {'Content-Type': 'application/json'}, 
        body: jsonEncode({'image': 'data:image/jpeg;base64,$base64Image', 'session_id': appSessionId})
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['faces'] != null && data['faces'].isNotEmpty) {
          final face = data['faces'][0];
          final emotionKey = face['emotion'].toString().toLowerCase();
          
          if (mounted) {
            setState(() {
              _faceDetected = true;
              _currentEmotion = emotionKey;
              _emotionProbability = face['probability'];

              if (_trackedEmotion != emotionKey) {
                _trackedEmotion = emotionKey;
                _emotionStartTime = DateTime.now();
              } else if (_emotionStartTime != null && !_emotionFinalized) {
                if (DateTime.now().difference(_emotionStartTime!).inSeconds >= 2) { // Faster detection (2s)
                  _emotionFinalized = true;
                  _stopCamera();
                  if (widget.onEmotionDetected != null) {
                    widget.onEmotionDetected!(emotionKey);
                  }
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Detection error: $e');
    } finally {
      _isCapturing = false;
    }
  }

  @override
  void dispose() {
    _stopCamera(fromDispose: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        forceMaterialTransparency: true,
        leading: const BackButton(color: Colors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          CameraPreview(_controller!),
          
          // Gradient Overlay
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
            ),
          ),
          
          // Floating Card Overlay
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Card(
              elevation: 0, // Remove elevation for glass effect
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5), // Glass border
              ),
              color: theme.colorScheme.surfaceContainerHigh.withOpacity(0.3), // More transparent
              clipBehavior: Clip.hardEdge, // Required for blur
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // The blur effect
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _faceDetected ? _currentEmotion.toUpperCase() : 'SCANNING...',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_faceDetected)
                        LinearProgressIndicator(
                          value: _emotionProbability,
                          borderRadius: BorderRadius.circular(8),
                          minHeight: 8,
                        )
                      else 
                        const LinearProgressIndicator(),
                    ],
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

// ---------------------------------------------------------------------------
// CHAT PAGE - Modern Conversation
// ---------------------------------------------------------------------------
class ChatPage extends StatefulWidget {
  final String emotion;
  const ChatPage({super.key, required this.emotion});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with AutomaticKeepAliveClientMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  
  bool _isListening = false;
  bool _isLoading = false;
  bool _isMuted = false;
  final String _apiUrl = 'http://localhost:5000/chat';

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
    _initializeTts();
    
    // Initial Greeting
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _sendMessage('', isInitial: true);
    });
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.8); // More natural pace
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _initializeSpeech() async => await _speech.initialize();

  void _startListening() async {
    if (await Permission.microphone.request().isGranted) {
      await _flutterTts.stop();
      setState(() => _isListening = true);
      
      await _speech.listen(
        onResult: (result) {
          if (mounted) setState(() => _textController.text = result.recognizedWords);
          
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _stopListening();
            _sendMessage(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2),
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    if (mounted) setState(() => _isListening = false);
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
    
    _scrollToBottom();

    try {
      final history = _messages.map((msg) => {'role': msg['role'] ?? 'user', 'content': msg['content'] ?? ''}).toList();
      final body = {
        'emotion': widget.emotion, 
        'message': isInitial ? 'The user is feeling ${widget.emotion}. Start the conversation.' : message,
        'history': history,
        'session_id': appSessionId, 
      };
      
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assistantMessage = data['message'] as String;
        
        if (mounted) {
          setState(() {
            _messages.add({'role': 'assistant', 'content': assistantMessage});
            _isLoading = false;
          });
          _scrollToBottom();
          _scrollToBottom();
          if (!_isMuted) {
            await _flutterTts.speak(assistantMessage);
          }
        }
      }
    } catch (e) {
      debugPrint('Chat Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent, 
          duration: const Duration(milliseconds: 300), 
          curve: Curves.easeOut
        );
      }
    });
  }

  @override
  void dispose() {
    _speech.cancel();
    _flutterTts.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, interior) => [
          SliverAppBar.large(
            title: Text('Emotion Chat'),
            actions: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _isMuted = !_isMuted;
                  });
                  if (_isMuted) {
                    _flutterTts.stop();
                  }
                },
                icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              )
            ],
          ),
        ],
        body: Column(
          children: [
            // Emotion Chip
            Container(
              margin: const EdgeInsets.all(8),
              child: Chip(
                avatar: const Icon(Icons.face_retouching_natural, size: 18),
                label: Text('Feeling ${widget.emotion.toUpperCase()}'),
                backgroundColor: colorScheme.secondaryContainer,
                side: BorderSide.none,
              ),
            ),
            
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg['role'] == 'user';
                  
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      decoration: BoxDecoration(
                        gradient: isUser 
                          ? LinearGradient(colors: [colorScheme.primary, colorScheme.tertiary]) 
                          : null,
                        color: isUser ? null : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                        ),
                        boxShadow: isUser ? [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ] : null,
                      ),
                      child: Text(
                        msg['content'] ?? '',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: isUser ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Input Area
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                   IconButton.filledTonal(
                    onPressed: _isListening ? _stopListening : _startListening,
                    icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                    style: IconButton.styleFrom(
                      backgroundColor: _isListening ? colorScheme.errorContainer : null,
                      foregroundColor: _isListening ? colorScheme.onErrorContainer : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                        onSubmitted: (val) => _sendMessage(val),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _isLoading ? null : () => _sendMessage(_textController.text),
                    icon: _isLoading 
                      ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary)) 
                      : const Icon(Icons.send),
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

// ---------------------------------------------------------------------------
// UTILITIES - Animations
// ---------------------------------------------------------------------------
class DoodlePainter extends CustomPainter {
  final Color color;
  final double animationValue;
  
  DoodlePainter({required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    
    // Float animation
    final floatY = math.sin(animationValue * 2 * math.pi) * 15;
    
    // Body (Blob)
    final path = Path();
    for (double i = 0; i <= 360; i += 10) {
      final rad = i * (math.pi / 180);
      final offset = math.sin(rad * 4 + animationValue * math.pi) * 8;
      final x = center.dx + (100 + offset) * math.cos(rad);
      final y = center.dy + floatY + (90 + offset) * math.sin(rad);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
    
    // Eyes
    paint.style = PaintingStyle.fill;
    final leftEyePos = Offset(center.dx - 30, center.dy + floatY - 20);
    final rightEyePos = Offset(center.dx + 30, center.dy + floatY - 20);
    
    // Blinking logic
    final blink = math.sin(animationValue * 8 * math.pi) > 0.95;
    if (blink) {
       canvas.drawLine(leftEyePos.translate(-10, 0), leftEyePos.translate(10, 0), paint..strokeWidth = 4);
       canvas.drawLine(rightEyePos.translate(-10, 0), rightEyePos.translate(10, 0), paint);
    } else {
       canvas.drawCircle(leftEyePos, 8, paint);
       canvas.drawCircle(rightEyePos, 8, paint);
    }
    
    // Smile
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 4;
    final smileRect = Rect.fromCircle(center: Offset(center.dx, center.dy + floatY + 20), radius: 25);
    canvas.drawArc(smileRect, 0.2, math.pi - 0.4, false, paint);
  }

  @override
  bool shouldRepaint(covariant DoodlePainter oldDelegate) => true;
}

class AnimatedBackgroundPainter extends CustomPainter {
  final Color color1;
  final Color color2;
  final double animationValue;

  AnimatedBackgroundPainter({required this.color1, required this.color2, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamic Gradient Mesh
    final paint = Paint();
    
    // Animated gradient center
    final alignX = math.sin(animationValue * 2 * math.pi) * 0.5;
    final alignY = math.cos(animationValue * 2 * math.pi) * 0.5;
    
    final gradient = RadialGradient(
      center: Alignment(alignX, alignY),
      radius: 1.5,
      colors: [color1.withOpacity(0.3), color2],
    );
    
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant AnimatedBackgroundPainter oldDelegate) => true;
}