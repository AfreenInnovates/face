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
import 'package:flutter_tts/flutter_tts.dart'; // Changed from audioplayers to flutter_tts
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Hide system UI overlays (navigation bar, status bar)
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  // Get available cameras
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
          LandingPage(cameras: widget.cameras),
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
  
  const LandingPage({super.key, required this.cameras});

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
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);
    
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 20000),
      vsync: this,
    )..repeat();
    
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera access is required to detect emotions'),
            backgroundColor: const Color(0xFFFF6B6B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          AnimatedBackground(
            rotateController: _rotateController,
          ),
          
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                child: _isLoading
                    ? _buildLoadingScreen()
                    : _buildMainScreen(size),
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
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.1),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF4D96FF).withOpacity(0.6),
                        const Color(0xFF4D96FF).withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '🎭',
                      style: TextStyle(fontSize: 60),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Opacity(
                opacity: 0.5 + (_pulseController.value * 0.5),
                child: const Text(
                  'Initializing...',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainScreen(Size size) {
    return Column(
      key: const ValueKey('main'),
      children: [
        const SizedBox(height: 40),
        
        // App title with animation
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 800),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Column(
            children: [
              const Text(
                'EMOTION',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 8,
                  height: 1,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'LENS',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4D96FF), Color(0xFFFFD93D)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4D96FF).withOpacity(0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'AI-Powered Emotion Recognition',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white38,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
        
        const Spacer(),
        
        // Floating emoji circle
        AnimatedBuilder(
          animation: _floatController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, math.sin(_floatController.value * math.pi * 2) * 15),
              child: _buildEmotionCircle(),
            );
          },
        ),
        
        const Spacer(),
        
        // Description
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1000),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: child,
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Experience real-time emotion detection powered by advanced neural networks',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white60,
                height: 1.5,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 48),
        
        // Main CTA button
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1200),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onTap: _requestCameraPermission,
            child: Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4D96FF), Color(0xFF6BCB77)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4D96FF).withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Start Detection',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildEmotionCircle() {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF4D96FF).withOpacity(0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          
          // Emotion emojis in circle
          ...List.generate(_emotions.length, (index) {
            final angle = (index * 2 * math.pi / _emotions.length) - math.pi / 2;
            final radius = 100.0;
            final x = math.cos(angle) * radius;
            final y = math.sin(angle) * radius;
            
            return AnimatedBuilder(
              animation: _rotateController,
              builder: (context, child) {
                final rotationAngle = _rotateController.value * 2 * math.pi;
                final currentAngle = angle + rotationAngle;
                final currentX = math.cos(currentAngle) * radius;
                final currentY = math.sin(currentAngle) * radius;
                
                return Transform.translate(
                  offset: Offset(currentX, currentY),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 800),
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _emotions[index].color.withOpacity(0.2),
                        border: Border.all(
                          color: _emotions[index].color.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _emotions[index].emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          
          // Center icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF4D96FF).withOpacity(0.3),
                  const Color(0xFF4D96FF).withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF4D96FF).withOpacity(0.5),
                width: 2,
              ),
            ),
            child: const Center(
              child: Text(
                '🎭',
                style: TextStyle(fontSize: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedBackground extends StatelessWidget {
  final AnimationController rotateController;
  
  const AnimatedBackground({
    super.key,
    required this.rotateController,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0A0E27),
                Color(0xFF1a1d3a),
                Color(0xFF0A0E27),
              ],
            ),
          ),
        ),
        
        // Animated orbs
        ...List.generate(3, (index) {
          return AnimatedBuilder(
            animation: rotateController,
            builder: (context, child) {
              final offset = (index * 0.33);
              final animValue = (rotateController.value + offset) % 1.0;
              
              return Positioned(
                top: -100 + (animValue * MediaQuery.of(context).size.height * 1.2),
                left: index == 1
                    ? MediaQuery.of(context).size.width * 0.7
                    : MediaQuery.of(context).size.width * 0.2,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        [
                          const Color(0xFF4D96FF),
                          const Color(0xFF6BCB77),
                          const Color(0xFFFFD93D),
                        ][index].withOpacity(0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
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
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  
  late AnimationController _scanController;
  late AnimationController _pulseController;
  bool _faceDetected = false;
  
  // Emotion tracking for 5 seconds
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
    _scanController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      return;
    }

    // Use front camera if available
    CameraDescription camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras[0],
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _startDetection();
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  bool _isCapturing = false;

  void _startDetection() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_controller != null && _controller!.value.isInitialized && !_isCapturing) {
        _detectEmotion();
      }
    });
  }

  Future<void> _detectEmotion() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing || _emotionFinalized) return;

    _isCapturing = true;
    try {
      final XFile image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image': 'data:image/jpeg;base64,$base64Image',
          'session_id': _sessionId,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['faces'] != null && data['faces'].isNotEmpty) {
          final face = data['faces'][0];
          final emotionKey = face['emotion'].toString().toLowerCase();
          final emotionData = _emotionMap[emotionKey] ?? 
              EmotionData('🎭', emotionKey, const Color(0xFF95A3B3));
          
          if (mounted) {
            final detectedEmotionKey = emotionKey;
            
            setState(() {
              _faceDetected = true;
              _currentEmotion = emotionData.name;
              _emotionProbability = face['probability'];
              _emotionColor = emotionData.color;
              
              // Track emotion for 5-7 seconds
              if (_trackedEmotion != detectedEmotionKey) {
                _trackedEmotion = detectedEmotionKey;
                _emotionStartTime = DateTime.now();
                _emotionFinalized = false;
                _emotionTrackingTimer?.cancel();
              } else if (_emotionStartTime != null && !_emotionFinalized) {
                final duration = DateTime.now().difference(_emotionStartTime!);
                if (duration.inSeconds >= 5) {
                  _emotionFinalized = true;
                  // Stop detection
                  _detectionTimer?.cancel();
                  // Stop camera
                  _controller?.dispose();
                  _controller = null;
                  
                  // Show success screen briefly, then navigate
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (widget.onEmotionDetected != null && mounted) {
                      widget.onEmotionDetected!(detectedEmotionKey);
                    }
                  });
                }
              }
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _faceDetected = false;
              _currentEmotion = 'No Face Detected';
              _emotionProbability = 0.0;
              _emotionColor = const Color(0xFF95A3B3);
              _trackedEmotion = null;
              _emotionStartTime = null;
            });
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('Previous capture')) {
        print('Skipping frame - camera busy');
      } else {
        print('Detection error: $e');
      }
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
    // Show success screen if emotion has been finalized
    if (_emotionFinalized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 80, color: _emotionColor),
              const SizedBox(height: 24),
              Text(
                'Emotion Captured!',
                style: TextStyle(
                  color: _emotionColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading screen if camera not initialized
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E27),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4D96FF)),
              ),
              SizedBox(height: 24),
              Text(
                'Initializing Camera...',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final emotionData = _emotionMap[_currentEmotion.toLowerCase()];
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
          
          // Scanning overlay when no face
          if (!_faceDetected)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scanController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: ScanLinePainter(
                      progress: _scanController.value,
                      color: const Color(0xFF4D96FF),
                    ),
                  );
                },
              ),
            ),
          
          // Gradient overlays
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 250,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Top emotion display
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    // Calculate time remaining for emotion tracking
                    int remainingSeconds = 0;
                    if (_emotionStartTime != null && _trackedEmotion != null) {
                      final elapsed = DateTime.now().difference(_emotionStartTime!).inSeconds;
                      remainingSeconds = 5 - elapsed;
                      if (remainingSeconds < 0) remainingSeconds = 0;
                    }
                    
                    return Transform.scale(
                      scale: _faceDetected ? 1.0 + (_pulseController.value * 0.03) : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _emotionColor.withOpacity(0.5),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _emotionColor.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Emoji and emotion name
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (emotionData != null) ...[
                                  Text(
                                    emotionData.emoji,
                                    style: const TextStyle(fontSize: 36),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                Text(
                                  _currentEmotion.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: _emotionColor,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                            
                            if (_faceDetected) ...[
                              const SizedBox(height: 16),
                              
                              // Countdown timer
                              if (_trackedEmotion != null && remainingSeconds > 0) ...[
                                Text(
                                  'Analyzing: ${remainingSeconds}s',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _emotionColor,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              
                              // Confidence bar
                              Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'CONFIDENCE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white54,
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${(_emotionProbability * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _emotionColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: TweenAnimationBuilder<double>(
                                      duration: const Duration(milliseconds: 300),
                                      tween: Tween(begin: 0.0, end: _emotionProbability),
                                      builder: (context, value, child) {
                                        return LinearProgressIndicator(
                                          value: value,
                                          minHeight: 6,
                                          backgroundColor: Colors.white.withOpacity(0.1),
                                          valueColor: AlwaysStoppedAnimation<Color>(_emotionColor),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Info button
                    _buildControlButton(
                      icon: Icons.info_outline,
                      onTap: () => _showInfoDialog(context),
                    ),
                    
                    // Close button - now just returns to navigation
                    _buildControlButton(
                      icon: Icons.close,
                      onTap: () {
                        // Navigation is handled by MainNavigation
                        // This button can be used for resetting emotion tracking
                        setState(() {
                          _trackedEmotion = null;
                          _emotionStartTime = null;
                          _emotionFinalized = false;
                        });
                      },
                      isPrimary: true,
                    ),
                    
                    // Settings button
                    _buildControlButton(
                      icon: Icons.settings_outlined,
                      onTap: () {
                        // Add settings functionality
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Status indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _faceDetected 
                    ? const Color(0xFF6BCB77).withOpacity(0.9)
                    : Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _faceDetected ? 'ACTIVE' : 'SEARCHING',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isPrimary 
              ? const Color(0xFFFF6B6B).withOpacity(0.9)
              : Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1a1d3a),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'About Emotion Lens',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This app uses a pre-trained deep learning model to detect facial emotions in real-time. The model analyzes facial features and classifies emotions into categories like happy, sad, angry, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'GOT IT',
                  style: TextStyle(
                    color: Color(0xFF4D96FF),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final y = size.height * progress;
    
    // Draw horizontal scan line
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      paint,
    );
    
    // Draw glow effect
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(ScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
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
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _initializeSpeech();
    _initializeTts();
    
    // Send initial greeting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendMessage('Hello!', isInitial: true);
    });
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.7);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _initializeSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() {
                _isListening = false;
              });
            }
          }
        },
        onError: (error) {
          print('Speech recognition error: $error');
          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        },
      );
      
      if (!available) {
        print('Speech recognition not available - this is normal on some browsers');
      }
    } catch (e) {
      print('Failed to initialize speech recognition: $e');
    }
  }

  void _startListening() async {
    try {
      // Check if speech recognition is available
      if (!_speech.isAvailable) {
        bool available = await _speech.initialize();
        if (!available) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Speech recognition not available'),
                backgroundColor: Color(0xFFFF6B6B),
              ),
            );
          }
          return;
        }
      }

      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required for voice input'),
              backgroundColor: Color(0xFFFF6B6B),
            ),
          );
        }
        return;
      }
      
      // Stop TTS if it's talking so we can listen
      await _flutterTts.stop();

      // Start listening
      setState(() {
        _isListening = true;
      });

      await _speech.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _textController.text = result.recognizedWords;
            });
            
            // Auto-send when silence is detected or result is final
            if (result.finalResult) {
              _stopListening();
              if (result.recognizedWords.isNotEmpty) {
                // Short delay to let the UI update
                Future.delayed(const Duration(milliseconds: 300), () {
                  _sendMessage(result.recognizedWords);
                });
              }
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  Future<void> _sendMessage(String message, {bool isInitial = false}) async {
    if (message.trim().isEmpty && !isInitial) return;

    // Stop previous speech if any
    await _flutterTts.stop();

    setState(() {
      if (!isInitial) {
        _messages.add({'role': 'user', 'content': message});
        _textController.clear();
      }
      _isLoading = true;
    });

    try {
      // Build conversation history
      final history = _messages.map((msg) => {
        'role': msg['role'] ?? 'user',
        'content': msg['content'] ?? ''
      }).toList();

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'emotion': widget.emotion,
          'message': isInitial ? 'Hello, I\'m feeling ${widget.emotion}. Can you help me?' : message,
          'history': history,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final assistantMessage = data['message'] as String;

        setState(() {
          _messages.add({'role': 'assistant', 'content': assistantMessage});
        });

        // Read out loud if not muted
        if (_isTtsEnabled) {
          await _flutterTts.speak(assistantMessage);
        }

      } else {
        throw Exception('Failed to get response from server');
      }
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF6B6B),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _toggleMute() {
    setState(() {
      _isTtsEnabled = !_isTtsEnabled;
    });
    if (!_isTtsEnabled) {
      _flutterTts.stop();
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
    final emotionData = _emotionMap[widget.emotion.toLowerCase()] ?? 
        EmotionData('😐', 'Neutral', const Color(0xFF95A3B3));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(
              emotionData.emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Emotion Chat',
              style: TextStyle(
                color: emotionData.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _toggleMute,
            icon: Icon(
              _isTtsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _isTtsEnabled ? emotionData.color : Colors.white54,
            ),
          ),
          const SizedBox(width: 8),
        ],
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Emotion indicator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: emotionData.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: emotionData.color.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Detected Emotion: ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                Text(
                  emotionData.name.toUpperCase(),
                  style: TextStyle(
                    color: emotionData.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          
          // Messages list
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
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF4D96FF).withOpacity(0.2)
                          : const Color(0xFF1a1d3a),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isUser
                            ? const Color(0xFF4D96FF).withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    child: Text(
                      message['content'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Loading indicator
          if (_isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(emotionData.color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(16),
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
            child: Row(
              children: [
                // Voice button
                GestureDetector(
                  onTap: _isLoading ? null : (_isListening ? _stopListening : _startListening),
                  child: AnimatedBuilder(
                    animation: _isListening ? _pulseController : const AlwaysStoppedAnimation(0),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isListening ? 1.0 + (_pulseController.value * 0.1) : 1.0,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _isListening
                                ? const Color(0xFFFF6B6B).withOpacity(0.3)
                                : const Color(0xFF4D96FF).withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isListening
                                  ? const Color(0xFFFF6B6B)
                                  : const Color(0xFF4D96FF),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening
                                ? const Color(0xFFFF6B6B)
                                : const Color(0xFF4D96FF),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                
                // Text input
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isListening 
                          ? Colors.white.withOpacity(0.05)
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _textController,
                      enabled: !_isListening && !_isLoading,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _isListening 
                            ? 'Listening...' 
                            : 'Type or speak your message...',
                        hintStyle: TextStyle(
                          color: _isListening 
                              ? const Color(0xFFFF6B6B)
                              : Colors.white54,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (text) {
                        if (text.trim().isNotEmpty && !_isLoading) {
                          _sendMessage(text);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Send button
                GestureDetector(
                  onTap: () {
                    if (_textController.text.trim().isNotEmpty && !_isLoading && !_isListening) {
                      _sendMessage(_textController.text);
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: emotionData.color.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: emotionData.color,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.send,
                      color: emotionData.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}