import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'face_anti_spoofing.dart';

class TFLiteService {
  static tfl.Interpreter? _faceNetInterpreter;
  
  static const int faceNetInputSize = 112;
  static const int embeddingSize = 192;
  static int _actualEmbeddingSize = embeddingSize; // Will be updated from model
  
  // Expose interpreter status for debugging
  static bool get isFaceNetLoaded => _faceNetInterpreter != null;
  
  static Future<void> initialize() async {
    try {
      // Initialize FaceNet model
      _faceNetInterpreter = await tfl.Interpreter.fromAsset(
        'assets/models/facenet.tflite',
        options: tfl.InterpreterOptions()..threads = 4,
      );
      print('✅ FaceNet model loaded successfully');
      
      // Print model info for debugging
      final inputTensor = _faceNetInterpreter!.getInputTensor(0);
      final outputTensor = _faceNetInterpreter!.getOutputTensor(0);
      print('📊 FaceNet Input shape: ${inputTensor.shape}, type: ${inputTensor.type}');
      print('📊 FaceNet Output shape: ${outputTensor.shape}, type: ${outputTensor.type}');
      
      // Update actual embedding size from model
      if (outputTensor.shape.length >= 2) {
        _actualEmbeddingSize = outputTensor.shape[1];
        print('📊 Actual embedding size: $_actualEmbeddingSize');
      }
      
      // Initialize anti-spoofing model
      await AntiSpoofingService.initialize();
      
    } catch (e) {
      print('⚠️ TFLite models loading failed: $e');
      print('Using fallback mode for demo');
    }
  }
  
  static Future<List<double>> generateEmbedding(img.Image face) async {
    if (_faceNetInterpreter == null) {
      print('⚠️ FaceNet not loaded, using fallback');
      return _generateFallbackEmbedding(face);
    }
    
    try {
      // Resize face to 112x112
      final resized = img.copyResize(face, width: faceNetInputSize, height: faceNetInputSize);
      
      // Normalize to [-1, 1]
      final input = _preprocessFace(resized);
      
      // Prepare output buffer using actual embedding size from model
      final outputSize = _actualEmbeddingSize;
      final output = List.generate(1, (_) => List.generate(outputSize, (_) => 0.0, growable: false), growable: false);
      
      // Run inference
      _faceNetInterpreter!.run(input, output);
      
      // Debug: print first few embedding values
      final rawEmbedding = output[0].toList();
      print('🔢 Raw embedding (first 5): ${rawEmbedding.take(5).map((e) => e.toStringAsFixed(4)).join(", ")}');
      print('🔢 Raw embedding sum: ${rawEmbedding.reduce((a, b) => a + b).toStringAsFixed(4)}');
      
      // Normalize embedding
      final normalized = normalizeEmbedding(rawEmbedding);
      print('🔢 Normalized (first 5): ${normalized.take(5).map((e) => e.toStringAsFixed(4)).join(", ")}');
      
      return normalized;
      
    } catch (e) {
      print('⚠️ FaceNet inference failed: $e');
      return _generateFallbackEmbedding(face);
    }
  }
  
  static List<List<List<List<double>>>> _preprocessFace(img.Image face) {
    // MobileFaceNet typically expects input normalized to [-1, 1]
    // Some models use different normalization - try standard ImageNet-style if this doesn't work
    return List.generate(
      1,
      (_) => List.generate(
        faceNetInputSize,
        (y) => List.generate(
          faceNetInputSize,
          (x) {
            final pixel = face.getPixel(x, y);
            // Standard normalization to [-1, 1]
            return [
              (pixel.r.toDouble() - 127.5) / 127.5,
              (pixel.g.toDouble() - 127.5) / 127.5,
              (pixel.b.toDouble() - 127.5) / 127.5,
            ];
          },
        ),
      ),
    );
  }
  
  static List<double> _generateFallbackEmbedding(img.Image face) {
    int imageHash = 0;
    
    for (int y = 0; y < face.height; y += 5) {
      for (int x = 0; x < face.width; x += 5) {
        final pixel = face.getPixel(x, y);
        imageHash = (imageHash * 31 + pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) & 0xFFFFFFFF;
      }
    }
    
    final random = math.Random(imageHash);
    // Use actual embedding size for fallback as well
    List<double> embedding = List.generate(_actualEmbeddingSize, (_) => random.nextDouble() * 2 - 1);
    
    return normalizeEmbedding(embedding);
  }
  
  static List<double> normalizeEmbedding(List<double> embedding) {
    double sum = embedding.fold(0.0, (a, b) => a + b * b);
    double magnitude = math.sqrt(sum);
    
    if (magnitude == 0) return embedding;
    
    return embedding.map((e) => e / magnitude).toList();
  }
  
  static Future<bool> checkLiveness(List<img.Image> frames) async {
    if (frames.isEmpty) return false;
    
    // Use the best quality frame (middle frame)
    final middleFrame = frames[frames.length ~/ 2];
    
    // Use anti-spoofing service
    return await AntiSpoofingService.checkLiveness(middleFrame);
  }
  
  static double euclideanDistance(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError('Embeddings must have the same length');
    }
    
    double sumSquares = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      sumSquares += diff * diff;
    }
    
    return math.sqrt(sumSquares);
  }
  
  static double cosineSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError('Embeddings must have the same length');
    }
    
    double dotProduct = 0.0;
    double magnitude1 = 0.0;
    double magnitude2 = 0.0;
    
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      magnitude1 += embedding1[i] * embedding1[i];
      magnitude2 += embedding2[i] * embedding2[i];
    }
    
    if (magnitude1 == 0 || magnitude2 == 0) return 0.0;
    
    return dotProduct / (math.sqrt(magnitude1) * math.sqrt(magnitude2));
  }
  
  static void dispose() {
    _faceNetInterpreter?.close();
    AntiSpoofingService.dispose();
  }
}
