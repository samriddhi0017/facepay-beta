import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/tflite_service.dart';

class CameraCaptureScreen extends StatefulWidget {
  final String mode; // 'enroll' or 'verify'
  
  const CameraCaptureScreen({super.key, required this.mode});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  bool _isInitialized = false;
  String _statusMessage = 'Initializing camera...';
  final List<img.Image> _capturedFrames = [];
  FaceDetector? _faceDetector;
  Timer? _captureTimer;
  final int _framesNeeded = 3;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeFaceDetector();
  }
  
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = 'Position your face in the guide';
        });
        
        _startAutoCapture();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Camera error: $e';
      });
    }
  }
  
  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      minFaceSize: 0.15, // More lenient - detect smaller faces
      performanceMode: FaceDetectorMode.fast,
    );
    _faceDetector = FaceDetector(options: options);
  }
  
  void _startAutoCapture() {
    _captureTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_capturedFrames.length >= _framesNeeded) {
        timer.cancel();
        await _processFrames();
        return;
      }
      
      if (!_isProcessing && _isInitialized) {
        await _captureFrame();
      }
    });
  }
  
  Future<void> _captureFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector!.processImage(inputImage);
      
      if (faces.isNotEmpty) {
        final bytes = await image.readAsBytes();
        final decodedImage = img.decodeImage(bytes);
        
        if (decodedImage != null) {
          final face = faces.first;
          final faceRect = face.boundingBox;
          
          // Crop face with padding
          final padding = 20;
          final left = (faceRect.left - padding).clamp(0, decodedImage.width - 1).toInt();
          final top = (faceRect.top - padding).clamp(0, decodedImage.height - 1).toInt();
          final right = (faceRect.right + padding).clamp(0, decodedImage.width).toInt();
          final bottom = (faceRect.bottom + padding).clamp(0, decodedImage.height).toInt();
          
          final croppedFace = img.copyCrop(
            decodedImage,
            x: left,
            y: top,
            width: right - left,
            height: bottom - top,
          );
          
          setState(() {
            _capturedFrames.add(croppedFace);
            _statusMessage = 'Capturing... ${_capturedFrames.length}/$_framesNeeded';
          });
        }
      } else {
        setState(() {
          _statusMessage = 'No face detected - please position yourself';
        });
      }
    } catch (e) {
      print('Frame capture error: $e');
    }
    
    setState(() => _isProcessing = false);
  }
  
  Future<void> _processFrames() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Checking liveness...';
    });
    
    try {
      // Check liveness
      bool isLive = await TFLiteService.checkLiveness(_capturedFrames);
      
      if (!isLive) {
        if (mounted) {
          Navigator.pop(context, {
            'success': false,
            'error': 'Liveness check failed',
          });
        }
        return;
      }
      
      setState(() {
        _statusMessage = 'Generating face signature...';
      });
      
      // Use best quality frame (middle frame)
      final bestFrame = _capturedFrames[_capturedFrames.length ~/ 2];
      
      // Generate embedding
      final embedding = await TFLiteService.generateEmbedding(bestFrame);
      
      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'embedding': embedding,
        });
      }
      
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, {
          'success': false,
          'error': e.toString(),
        });
      }
    }
  }
  
  @override
  void dispose() {
    _captureTimer?.cancel();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      body: Stack(
        children: [
          // Camera Preview
          if (_isInitialized && _cameraController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          
          // Dark overlay outside face guide
          CustomPaint(
            painter: OverlayPainter(),
            child: Container(),
          ),
          
          // Geometric Face Guide Overlay
          CustomPaint(
            painter: FaceGuidePainter(),
            child: Container(),
          ),
          
          // Grid Texture Overlay
          CustomPaint(
            painter: GridPainter(),
            child: Container(),
          ),
          
          // Status Bar
          Positioned(
            top: 60,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F12).withOpacity(0.85),
                border: Border.all(color: const Color(0xFF00F5D4), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  if (_isProcessing)
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 12),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F5D4)),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Color(0xFFF8F9FA),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Progress Indicator
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _framesNeeded,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index < _capturedFrames.length
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFFF8F9FA).withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Cancel Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFFF2E63), width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    backgroundColor: const Color(0xFF0F0F12).withOpacity(0.85),
                  ),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Color(0xFFFF2E63),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
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

class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF8F9FA).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    // Face-sized guide positioned for better capture
    final center = Offset(size.width / 2, size.height * 0.4);
    final ovalWidth = size.width * 0.7; // Larger for easier alignment
    final ovalHeight = size.height * 0.45; // Taller for full face
    
    final rect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );
    
    // Draw oval face guide
    canvas.drawOval(rect, paint);
    
    // Corner markers - smaller and cleaner
    final cornerSize = 15.0;
    final cornerPaint = Paint()
      ..color = const Color(0xFF00F5D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    // Top-left corner
    canvas.drawLine(
      Offset(rect.left - 10, rect.top),
      Offset(rect.left - 10 + cornerSize, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left - 10, rect.top),
      Offset(rect.left - 10, rect.top + cornerSize),
      cornerPaint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(rect.right + 10, rect.top),
      Offset(rect.right + 10 - cornerSize, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right + 10, rect.top),
      Offset(rect.right + 10, rect.top + cornerSize),
      cornerPaint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(rect.left - 10, rect.bottom),
      Offset(rect.left - 10 + cornerSize, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left - 10, rect.bottom),
      Offset(rect.left - 10, rect.bottom - cornerSize),
      cornerPaint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(rect.right + 10, rect.bottom),
      Offset(rect.right + 10 - cornerSize, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right + 10, rect.bottom),
      Offset(rect.right + 10, rect.bottom - cornerSize),
      cornerPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000).withOpacity(0.6);
    
    final center = Offset(size.width / 2, size.height * 0.4);
    final ovalWidth = size.width * 0.7;
    final ovalHeight = size.height * 0.45;
    
    final rect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );
    
    // Create path with hole for face guide
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(rect)
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F5D4).withOpacity(0.02)
      ..strokeWidth = 1.0;
    
    const spacing = 40.0;
    
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
