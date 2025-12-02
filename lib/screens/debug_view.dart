import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:hive_flutter/hive_flutter.dart';
import '../services/tflite_service.dart';
import '../models/student.dart';

class DebugView extends StatefulWidget {
  const DebugView({super.key});

  @override
  State<DebugView> createState() => _DebugViewState();
}

class _DebugViewState extends State<DebugView> {
  CameraController? _camera;
  CameraDescription? _cameraDescription;
  bool _isDetecting = false;
  List<Face> _faces = [];
  FaceDetector? _faceDetector;
  bool _isEnrolling = false;
  bool _isVerifying = false;
  String _statusMessage = '';
  CameraImage? _latestImage;
  String? _matchedName;
  double? _matchConfidence;
  bool _isVerifyingRealtime = false;
  int _skipFrameCount = 0;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: true,
      ),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    print('🚀 INIT: Starting camera initialization...');
    
    final cameras = await availableCameras();
    print('🚀 INIT: Found ${cameras.length} cameras');
    
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    print('🚀 INIT: Selected front camera: ${frontCamera.name}');

    _cameraDescription = frontCamera;

    _camera = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    print('🚀 INIT: Initializing camera controller...');
    await _camera!.initialize();
    print('🚀 INIT: Camera controller initialized');

    if (mounted) {
      setState(() {});
      print('🚀 INIT: Starting image stream...');
      await _camera!.startImageStream((image) {
        _latestImage = image;
        if (_isDetecting) return;
        _isDetecting = true;
        _detectFaces(image);
      });
      print('🚀 INIT: Image stream started successfully');
    }
  }

  Future<void> _detectFaces(CameraImage image) async {
    final inputImage = _buildInputImage(image);
    if (inputImage == null) {
      _isDetecting = false;
      return;
    }
    
    try {
      final faces = await _faceDetector!.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
        });
        
        // Real-time verification - skip frames for performance
        _skipFrameCount++;
        
        // Check if face exists AND not already processing
        if (faces.isNotEmpty && !_isEnrolling && !_isVerifyingRealtime) {
          // Check face size before verification
          final face = faces.first;
          final faceWidth = face.boundingBox.width;
          final faceHeight = face.boundingBox.height;
          
          if (faceWidth >= 112 && faceHeight >= 112 && _skipFrameCount >= 15) {
            _skipFrameCount = 0;
            _verifyFaceRealtime(image, face); // Run async
          } else if (_skipFrameCount >= 15) {
            _skipFrameCount = 0;
          }
        } else if (faces.isEmpty) {
          // Clear match info when no face detected
          if (mounted && _matchedName != null) {
            setState(() {
              _matchedName = null;
              _matchConfidence = null;
            });
          }
        }
      }
    } catch (e) {
      print('❌ Detection error: $e');
    }

    _isDetecting = false;
  }

  Future<void> _verifyFaceRealtime(CameraImage image, Face face) async {
    if (_isVerifyingRealtime) return;
    _isVerifyingRealtime = true;
    
    try {
      // Convert and crop face
      final faceImage = await _cropFaceFromCamera(image, face);
      
      // Generate embedding
      final embedding = await TFLiteService.generateEmbedding(faceImage);
      
      // Search database
      final box = await Hive.openBox<Student>('students');
      
      if (box.isEmpty) {
        if (mounted) {
          setState(() {
            _matchedName = null;
            _matchConfidence = null;
          });
        }
        return;
      }

      double bestDistance = double.infinity;
      Student? bestMatch;

      for (var student in box.values) {
        final distance = TFLiteService.euclideanDistance(
          embedding,
          student.faceEmbedding,
        );

        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = student;
        }
      }

      // Always show the nearest match - no threshold
      if (bestMatch != null) {
        // Convert distance to confidence percentage
        // Lower distance = higher confidence
        // Distance typically ranges 0-2 for normalized embeddings
        final confidence = (1.0 - (bestDistance / 2.0)).clamp(0.0, 1.0);
        
        if (mounted) {
          setState(() {
            _matchedName = bestMatch!.name;
            _matchConfidence = confidence;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _matchedName = null;
            _matchConfidence = null;
          });
        }
      }
      
    } catch (e) {
      print('❌ Realtime verification error: $e');
    } finally {
      _isVerifyingRealtime = false;
    }
  }

  Future<void> _enrollFace() async {
    if (_latestImage == null || _faces.isEmpty) {
      setState(() => _statusMessage = '❌ No face detected');
      return;
    }

    setState(() {
      _isEnrolling = true;
      _statusMessage = 'Processing...';
    });

    try {
      // Convert CameraImage to img.Image
      final faceImage = await _cropFaceFromCamera(_latestImage!, _faces.first);
      
      // Generate embedding
      final embedding = await TFLiteService.generateEmbedding(faceImage);
      
      // Get name from user
      if (!mounted) return;
      final name = await _showNameDialog();
      if (name == null || name.isEmpty) {
        setState(() {
          _isEnrolling = false;
          _statusMessage = 'Enrollment cancelled';
        });
        return;
      }

      // Save to database
      final box = await Hive.openBox<Student>('students');
      final student = Student(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        balance: 1000.0,
        faceEmbedding: embedding,
        enrolledAt: DateTime.now(),
      );
      await box.put(student.id, student);
      
      setState(() {
        _isEnrolling = false;
        _statusMessage = '✅ Enrolled: $name';
      });
      
    } catch (e) {
      setState(() {
        _isEnrolling = false;
        _statusMessage = '❌ Error: $e';
      });
    }
  }

  Future<void> _verifyFace() async {
    if (_latestImage == null || _faces.isEmpty) {
      setState(() => _statusMessage = '❌ No face detected');
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusMessage = 'Verifying...';
    });

    try {
      // Convert and crop face
      final faceImage = await _cropFaceFromCamera(_latestImage!, _faces.first);
      
      // Generate embedding
      final embedding = await TFLiteService.generateEmbedding(faceImage);
      
      // Search database
      final box = await Hive.openBox<Student>('students');
      
      if (box.isEmpty) {
        setState(() {
          _isVerifying = false;
          _statusMessage = '⚠️ No students enrolled';
        });
        return;
      }

      double bestDistance = double.infinity;
      Student? bestMatch;

      for (var student in box.values) {
        final distance = TFLiteService.euclideanDistance(
          embedding,
          student.faceEmbedding,
        );

        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = student;
        }
      }

      final threshold = 1.2; // Same threshold as realtime

      if (bestMatch != null && bestDistance < threshold) {
        setState(() {
          _isVerifying = false;
          final confidence = ((1.0 - (bestDistance / 2.0)) * 100).clamp(0.0, 100.0);
          _statusMessage = '✅ Matched: ${bestMatch!.name}\nDistance: ${bestDistance.toStringAsFixed(3)}\nConfidence: ${confidence.toStringAsFixed(1)}%';
        });
      } else {
        setState(() {
          _isVerifying = false;
          _statusMessage = '❌ No match found\nBest distance: ${bestDistance.toStringAsFixed(3)}';
        });
      }
      
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _statusMessage = '❌ Error: $e';
      });
    }
  }

  Future<img.Image> _cropFaceFromCamera(CameraImage cameraImage, Face face) async {
    // Convert NV21 to RGB (proper color conversion)
    final imgLib = img.Image(
      width: cameraImage.width,
      height: cameraImage.height,
    );

    final yPlane = cameraImage.planes[0].bytes;
    final uvPlane = cameraImage.planes[1].bytes;
    
    for (int y = 0; y < cameraImage.height; y++) {
      for (int x = 0; x < cameraImage.width; x++) {
        final yIndex = y * cameraImage.planes[0].bytesPerRow + x;
        final uvIndex = (y ~/ 2) * cameraImage.planes[1].bytesPerRow + (x ~/ 2) * 2;
        
        final yValue = yPlane[yIndex];
        final uValue = uvPlane[uvIndex] - 128;
        final vValue = uvPlane[uvIndex + 1] - 128;
        
        // YUV to RGB conversion
        int r = (yValue + 1.402 * vValue).clamp(0, 255).toInt();
        int g = (yValue - 0.344136 * uValue - 0.714136 * vValue).clamp(0, 255).toInt();
        int b = (yValue + 1.772 * uValue).clamp(0, 255).toInt();
        
        imgLib.setPixelRgb(x, y, r, g, b);
      }
    }

    // Crop face region with padding
    final box = face.boundingBox;
    final padding = 20;
    final left = (box.left - padding).clamp(0, cameraImage.width - 1).toInt();
    final top = (box.top - padding).clamp(0, cameraImage.height - 1).toInt();
    final right = (box.right + padding).clamp(0, cameraImage.width - 1).toInt();
    final bottom = (box.bottom + padding).clamp(0, cameraImage.height - 1).toInt();

    return img.copyCrop(
      imgLib,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Student Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  InputImage? _buildInputImage(CameraImage image) {
    final sensorOrientation = _cameraDescription?.sensorOrientation ?? 0;
    
    InputImageRotation? rotation;

    if (sensorOrientation == 0) {
      rotation = InputImageRotation.rotation0deg;
    } else if (sensorOrientation == 90) {
      rotation = InputImageRotation.rotation90deg;
    } else if (sensorOrientation == 180) {
      rotation = InputImageRotation.rotation180deg;
    } else if (sensorOrientation == 270) {
      rotation = InputImageRotation.rotation270deg;
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _camera?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_camera == null || !_camera!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Camera
          SizedBox(
            width: size.width,
            height: size.height,
            child: CameraPreview(_camera!),
          ),

          // Face boxes with match info
          if (_faces.isNotEmpty)
            SizedBox(
              width: size.width,
              height: size.height,
              child: CustomPaint(
                painter: FacePainter(
                  faces: _faces,
                  imageSize: _camera!.value.previewSize!,
                  screenSize: size,
                  isFrontCamera: true,
                  matchedName: _matchedName,
                  matchConfidence: _matchConfidence,
                ),
              ),
            ),

          // Status
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _faces.isNotEmpty ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _faces.isNotEmpty 
                        ? 'DETECTED ${_faces.length} FACE(S)' 
                        : 'NO FACE',
                    style: TextStyle(
                      color: _faces.isNotEmpty ? Colors.green : Colors.red,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_faces.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Face: ${_faces.first.boundingBox.width.toInt()}x${_faces.first.boundingBox.height.toInt()}px',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _faces.first.boundingBox.width >= 112 && _faces.first.boundingBox.height >= 112
                          ? '✅ Good for embeddings'
                          : '⚠️ Too small for embeddings',
                      style: TextStyle(
                        color: _faces.first.boundingBox.width >= 112 ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action Buttons
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isEnrolling || _faces.isEmpty ? null : _enrollFace,
                    icon: _isEnrolling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.person_add),
                    label: const Text('ENROLL'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isVerifying || _faces.isEmpty ? null : _verifyFace,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.verified_user),
                    label: const Text('VERIFY'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final Size screenSize;
  final bool isFrontCamera;
  final String? matchedName;
  final double? matchConfidence;

  FacePainter({
    required this.faces,
    required this.imageSize,
    required this.screenSize,
    this.isFrontCamera = true,
    this.matchedName,
    this.matchConfidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0; // Thicker for better visibility

    // Swap dimensions because camera preview is rotated
    final double scaleX = screenSize.width / imageSize.height;
    final double scaleY = screenSize.height / imageSize.width;

    for (final face in faces) {
      // Get face coordinates
      double left = face.boundingBox.left;
      double right = face.boundingBox.right;
      double top = face.boundingBox.top;
      double bottom = face.boundingBox.bottom;

      // Apply mirror effect for front camera
      if (isFrontCamera) {
        final temp = left;
        left = imageSize.height - right;
        right = imageSize.height - temp;
      }

      // Scale to screen size
      left *= scaleX;
      right *= scaleX;
      top *= scaleY;
      bottom *= scaleY;

      // Determine color based on match status
      Color boxColor;
      if (matchedName != null && matchedName != "Unknown") {
        if (matchConfidence != null && matchConfidence! > 0.6) {
          boxColor = Colors.green;
        } else if (matchConfidence != null && matchConfidence! > 0.4) {
          boxColor = Colors.orange;
        } else {
          boxColor = Colors.red;
        }
      } else if (matchedName == "Unknown") {
        boxColor = Colors.red;
      } else {
        boxColor = Colors.blue; // Searching/Processing
      }
      
      paint.color = boxColor;

      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        paint,
      );

      // Always draw label (even if just "Searching...")
      String displayText;
      if (matchedName != null && matchedName != "Unknown" && matchConfidence != null) {
        displayText = '$matchedName\n${(matchConfidence! * 100).toStringAsFixed(0)}%';
      } else if (matchedName == "Unknown") {
        displayText = 'Unknown Person';
      } else {
        displayText = 'Searching...';
      }
      
      final textSpan = TextSpan(
        text: displayText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          height: 1.2,
          shadows: [
            const Shadow(
              blurRadius: 8.0,
              color: Colors.black,
              offset: Offset(2.0, 2.0),
            ),
          ],
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Draw background rectangle for text
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left - 4,
          top - textPainter.height - 16,
          textPainter.width + 8,
          textPainter.height + 8,
        ),
        const Radius.circular(6),
      );
      
      final bgPaint = Paint()..color = boxColor.withOpacity(0.9);
      canvas.drawRRect(bgRect, bgPaint);
      
      // Position text above the bounding box
      final textOffset = Offset(
        left,
        (top - textPainter.height - 12).clamp(0.0, screenSize.height - textPainter.height),
      );
      
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}