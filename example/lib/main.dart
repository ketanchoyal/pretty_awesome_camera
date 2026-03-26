import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin.dart';
import 'package:waffle_camera_plugin/waffle_camera_plugin_platform_interface.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waffle Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  final _platform = WaffleCameraPluginPlatform.instance;

  // Camera state
  List<CameraDescription> _cameras = [];
  int? _selectedCameraIndex;
  int? _cameraId;
  int? _textureId;

  // Recording state
  bool _isInitializing = false;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSwitching = false;
  String? _errorMessage;
  String? _recordedFilePath;

  // Timer
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // Animation controllers
  late AnimationController _recordButtonController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _blinkController;

  RecordingState _recordingState = RecordingState.idle;
  StreamSubscription<RecordingState>? _recordingStateSubscription;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadCameras();
  }

  void _initAnimations() {
    _recordButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseController.repeat(reverse: true);
    _blinkController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingStateSubscription?.cancel();
    _disposeCamera();
    _recordButtonController.dispose();
    _pulseController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  // Timer methods
  void _startTimer() {
    _recordingTimer?.cancel();
    _recordingSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _recordingSeconds++;
        });
      }
    });
  }

  void _stopTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  void _pauseTimer() {
    // Timer keeps running but we don't increment in callback
  }

  void _resumeTimer() {
    // Timer continues, increment resumes in callback
  }

  String get _formattedTime {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // Camera operations
  Future<void> _loadCameras() async {
    try {
      final cameras = await _platform.getAvailableCameras();
      setState(() {
        _cameras = cameras;
        if (cameras.isNotEmpty) {
          _selectedCameraIndex = 0;
          // Auto-initialize first camera
          _initializeCamera();
        }
      });
    } on PlatformException catch (e) {
      _showError('Failed to get cameras: ${e.message}');
    }
  }

  Future<void> _initializeCamera() async {
    if (_selectedCameraIndex == null || _cameras.isEmpty) return;

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      await _disposeCamera();

      final camera = _cameras[_selectedCameraIndex!];

      final cameraId = await _platform.createCamera(
        camera,
        ResolutionPreset.high,
      );
      _cameraId = cameraId;

      final textureId = await _platform.initializeCamera(cameraId);

      _recordingStateSubscription = _platform
          .onRecordingStateChanged(cameraId)
          .listen((state) {
            setState(() {
              _recordingState = state;
            });
          });

      setState(() {
        _textureId = textureId;
        _isInitializing = false;
        _recordedFilePath = null;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: ${e.message}';
        _isInitializing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraId != null) {
      await _recordingStateSubscription?.cancel();
      _recordingStateSubscription = null;

      try {
        await _platform.disposeCamera(_cameraId!);
      } catch (e) {
        // Ignore dispose errors
      }

      setState(() {
        _cameraId = null;
        _textureId = null;
        _isRecording = false;
        _isPaused = false;
        _recordingState = RecordingState.idle;
      });

      _stopTimer();
      _recordingSeconds = 0;
    }
  }

  Future<void> _startRecording() async {
    if (_cameraId == null) return;

    try {
      await _platform.startRecording(_cameraId!);
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordedFilePath = null;
      });
      _startTimer();
      _recordButtonController.forward();
    } on PlatformException catch (e) {
      _showError('Failed to start recording: ${e.message}');
    }
  }

  Future<void> _pauseRecording() async {
    if (_cameraId == null) return;

    try {
      await _platform.pauseRecording(_cameraId!);
      setState(() {
        _isPaused = true;
      });
    } on PlatformException catch (e) {
      _showError('Failed to pause recording: ${e.message}');
    }
  }

  Future<void> _resumeRecording() async {
    if (_cameraId == null) return;

    try {
      await _platform.resumeRecording(_cameraId!);
      setState(() {
        _isPaused = false;
      });
    } on PlatformException catch (e) {
      _showError('Failed to resume recording: ${e.message}');
    }
  }

  Future<void> _stopRecording() async {
    if (_cameraId == null) return;

    try {
      final filePath = await _platform.stopRecording(_cameraId!);
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _recordedFilePath = filePath;
      });
      _stopTimer();
      _recordButtonController.reverse();
    } on PlatformException catch (e) {
      _showError('Failed to stop recording: ${e.message}');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _cameraId == null) return;

    if (_isRecording) {
      await _switchCameraDuringRecording();
    } else {
      setState(() {
        _selectedCameraIndex = (_selectedCameraIndex! + 1) % _cameras.length;
      });
      await _initializeCamera();
    }
  }

  Future<void> _switchCameraDuringRecording() async {
    final canSwitch = await _platform.canSwitchCurrentCamera;
    if (!canSwitch) {
      _showError('Camera switching not supported while recording');
      return;
    }

    setState(() {
      _isSwitching = true;
    });

    try {
      final newTextureId = await _platform.switchCamera(_cameraId!);

      setState(() {
        _textureId = newTextureId;
        _selectedCameraIndex = (_selectedCameraIndex! + 1) % _cameras.length;
      });
    } on PlatformException catch (e) {
      _showError('Failed to switch camera: ${e.message}');
    } finally {
      setState(() {
        _isSwitching = false;
      });
    }
  }

  Future<void> _saveToGallery() async {
    if (_recordedFilePath == null) return;

    try {
      PermissionStatus status;

      if (Platform.isIOS) {
        status = await Permission.photos.status;
        if (status.isDenied || status.isRestricted) {
          status = await Permission.photos.request();
        }
      } else {
        if (Platform.isAndroid) {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          final sdkInt = androidInfo.version.sdkInt;

          if (sdkInt >= 33) {
            status = await Permission.photos.status;
            if (status.isDenied) {
              status = await Permission.photos.request();
            }
          } else {
            status = await Permission.storage.status;
            if (status.isDenied) {
              status = await Permission.storage.request();
            }
          }
        } else {
          status = await Permission.storage.status;
          if (status.isDenied) {
            status = await Permission.storage.request();
          }
        }
      }

      if (status.isGranted || status.isLimited) {
        try {
          await Gal.putVideo(_recordedFilePath!);
          if (mounted) {
            _showSuccess('Video saved to gallery');
          }
        } catch (e) {
          _showError('Failed to save video: $e');
        }
      } else if (status.isDenied) {
        _showError('Permission denied. Allow access to save videos.');
      } else if (status.isPermanentlyDenied) {
        _showError('Enable in Settings > Privacy > Photos');
      }
    } catch (e) {
      _showError('Error saving: $e');
    }
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );

    // Clear error after showing
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: _isRecording ? _buildRecordingIndicator() : null,
        centerTitle: true,
        actions: [
          if (!_isRecording && _cameras.length > 1)
            IconButton(
              onPressed: _isInitializing ? null : _switchCamera,
              icon: const Icon(CupertinoIcons.switch_camera),
              color: Colors.white,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          _buildCameraPreview(),

          // Loading overlay when switching
          if (_isSwitching)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Pause overlay
          if (_isPaused)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Icon(Icons.pause, size: 80, color: Colors.white70),
              ),
            ),

          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Flash button (placeholder)
                  _buildFlashButton(),

                  // Camera switch during recording
                  if (_isRecording && _cameras.length > 1)
                    GestureDetector(
                      onTap: _isSwitching ? null : _switchCamera,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: _isSwitching
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                CupertinoIcons.switch_camera,
                                color: Colors.white,
                                size: 24,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 30,
                top: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: _recordedFilePath != null && !_isRecording
                    ? _buildPlaybackControls()
                    : _buildRecordingControls(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashButton() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Icon(
        CupertinoIcons.bolt_slash_fill,
        color: Colors.white70,
        size: 22,
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _blinkController,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'REC',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formattedTime,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_isInitializing && _textureId == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_textureId != null) {
      return CameraPreview(cameraId: _textureId!);
    }

    if (_cameras.isEmpty) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No cameras available',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Tap the button below to start',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Gallery/Last video placeholder
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: const Icon(
            Icons.photo_library_outlined,
            color: Colors.white70,
            size: 28,
          ),
        ),

        // Record button
        GestureDetector(
          onTap: _isRecording
              ? _stopRecording
              : (_isInitializing ? null : _startRecording),
          onLongPress: _isRecording && !_isPaused ? _pauseRecording : null,
          child: AnimatedBuilder(
            animation: _recordButtonController,
            builder: (context, child) {
              return AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isRecording && !_isPaused
                        ? _pulseAnimation.value
                        : 1.0,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isRecording ? 30 : 65,
                          height: _isRecording ? 30 : 65,
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.red
                                : Colors.red.shade600,
                            borderRadius: BorderRadius.circular(
                              _isRecording ? 8 : 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Pause/Resume button
        GestureDetector(
          onTap: _isRecording
              ? (_isPaused ? _resumeRecording : _pauseRecording)
              : null,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _isRecording ? Colors.white24 : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              color: _isRecording ? Colors.white : Colors.white38,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Video info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.shade900.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Video recorded ($_formattedTime)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Retake button
            _buildActionButton(
              icon: Icons.refresh,
              label: 'Retake',
              color: Colors.grey.shade700,
              onTap: () {
                setState(() {
                  _recordedFilePath = null;
                  _recordingSeconds = 0;
                });
              },
            ),

            // Save button
            _buildActionButton(
              icon: Icons.save_alt,
              label: 'Save',
              color: Colors.green.shade600,
              onTap: _saveToGallery,
            ),

            // Share button
            _buildActionButton(
              icon: Icons.share,
              label: 'Share',
              color: Colors.blue.shade600,
              onTap: () {
                _showSuccess('Share functionality coming soon!');
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
