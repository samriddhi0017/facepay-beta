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
    final cameras = await availableCameras();
    
    if (cameras.isEmpty) {
      // No cameras available
      return;
    }
    
    // Try to find front camera, fallback to first available camera
    CameraDescription selectedCamera;
    try {
      selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
    } catch (e) {
      // No front camera found, use first available (for emulators)
      selectedCamera = cameras.first;
    }

    _cameraDescription = selectedCamera;

    _camera = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _camera!.initialize();

    if (mounted) {
      setState(() {});
      await _camera!.startImageStream((image) {
        _latestImage = image;
        if (_isDetecting) return;
        _isDetecting = true;
        _detectFaces(image);
      });
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
      // Silent catch for detection errors
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

      print('🔍 Comparing against ${box.values.length} enrolled students');
      
      for (var student in box.values) {
        final distance = TFLiteService.euclideanDistance(
          embedding,
          student.faceEmbedding,
        );
        
        print('🔍 Distance to ${student.name}: ${distance.toStringAsFixed(4)}');

        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = student;
        }
      }
      
      print('🔍 Best match: ${bestMatch?.name} with distance: ${bestDistance.toStringAsFixed(4)}');

      // Threshold for face matching
      // For normalized embeddings, distance < 1.0 is typically a good match
      // Lower threshold = stricter matching
      const double matchThreshold = 1.0;
      
      if (bestMatch != null && bestDistance < matchThreshold) {
        // Convert distance to confidence percentage
        // Lower distance = higher confidence
        final confidence = (1.0 - (bestDistance / 1.5)).clamp(0.0, 1.0);
        
        if (mounted) {
          setState(() {
            _matchedName = bestMatch!.name;
            _matchConfidence = confidence;
          });
        }
      } else {
        // No match found - unknown person
        if (mounted) {
          setState(() {
            _matchedName = "Unknown";
            _matchConfidence = null;
          });
        }
      }
      
    } catch (e) {
      // Silent catch - realtime verification errors are expected occasionally
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
        _statusMessage = '❌ Enrollment failed';
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

      final threshold = 1.0; // Same threshold as realtime

      if (bestMatch != null && bestDistance < threshold) {
        setState(() {
          _isVerifying = false;
          final confidence = ((1.0 - (bestDistance / 1.5)) * 100).clamp(0.0, 100.0);
          _statusMessage = '✅ Matched: ${bestMatch!.name}\nDistance: ${bestDistance.toStringAsFixed(3)}\nConfidence: ${confidence.toStringAsFixed(1)}%';
        });
      } else {
        setState(() {
          _isVerifying = false;
          _statusMessage = '❌ Unknown person\nNearest distance: ${bestDistance.toStringAsFixed(3)}\n(threshold: $threshold)';
        });
      }
      
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _statusMessage = '❌ Error: $e';
      });
    }
  }

  Future<void> _clearAllEnrollments() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Enrollments?'),
        content: const Text('This will delete all enrolled faces. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final box = await Hive.openBox<Student>('students');
      await box.clear();
      setState(() {
        _statusMessage = '🗑️ All enrollments cleared';
        _matchedName = null;
        _matchConfidence = null;
      });
    }
  }

  Future<img.Image> _cropFaceFromCamera(CameraImage cameraImage, Face face) async {
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    // Create output image
    final imgLib = img.Image(width: width, height: height);

    final yPlane = cameraImage.planes[0].bytes;
    final yRowStride = cameraImage.planes[0].bytesPerRow;
    
    // Check if we have UV plane (NV21 format)
    if (cameraImage.planes.length > 1) {
      final uvPlane = cameraImage.planes[1].bytes;
      final uvRowStride = cameraImage.planes[1].bytesPerRow;
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          // Y plane index
          final yIndex = y * yRowStride + x;
          if (yIndex >= yPlane.length) continue;
          
          // UV plane index - NV21 has interleaved VU pairs
          final uvIndex = (y ~/ 2) * uvRowStride + (x & ~1);
          
          final yValue = yPlane[yIndex];
          int uValue = 0;
          int vValue = 0;
          
          // Safe UV access
          if (uvIndex < uvPlane.length) {
            vValue = uvPlane[uvIndex] - 128;
          }
          if (uvIndex + 1 < uvPlane.length) {
            uValue = uvPlane[uvIndex + 1] - 128;
          }
          
          // YUV to RGB conversion
          int r = (yValue + 1.402 * vValue).round().clamp(0, 255);
          int g = (yValue - 0.344136 * uValue - 0.714136 * vValue).round().clamp(0, 255);
          int b = (yValue + 1.772 * uValue).round().clamp(0, 255);
          
          imgLib.setPixelRgb(x, y, r, g, b);
        }
      }
    } else {
      // Grayscale fallback if no UV plane
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yRowStride + x;
          if (yIndex >= yPlane.length) continue;
          final yValue = yPlane[yIndex];
          imgLib.setPixelRgb(x, y, yValue, yValue, yValue);
        }
      }
    }

    // Crop face region with padding
    final box = face.boundingBox;
    final padding = 20;
    final left = (box.left - padding).clamp(0, width - 1).toInt();
    final top = (box.top - padding).clamp(0, height - 1).toInt();
    final right = (box.right + padding).clamp(0, width - 1).toInt();
    final bottom = (box.bottom + padding).clamp(0, height - 1).toInt();
    
    // Ensure valid crop dimensions
    final cropWidth = (right - left).clamp(1, width);
    final cropHeight = (bottom - top).clamp(1, height);

    return img.copyCrop(
      imgLib,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
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
                      _statusMessage.startsWith('❌') 
                          ? _statusMessage 
                          : _statusMessage,
                      style: TextStyle(
                        color: _statusMessage.startsWith('❌') 
                            ? Colors.redAccent 
                            : Colors.cyanAccent,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _clearAllEnrollments,
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: const Text('Clear All Enrolled Faces'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
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