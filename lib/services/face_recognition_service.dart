import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

/// Fixed face recognition service with proper cosine distance and debugging
class FaceRecognitionService {
  static tfl.Interpreter? _interpreter;
  static const int inputSize = 160; // Standard FaceNet/MobileFaceNet size
  static int _embeddingSize = 192;

  static bool get isModelLoaded => _interpreter != null;
  static int get embeddingSize => _embeddingSize;

  static Future<void> initialize() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset(
        'assets/models/facenet.tflite',
        options: tfl.InterpreterOptions()..threads = 4,
      );

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      
      // Update embedding size from model
      if (outputTensor.shape.length >= 2) {
        _embeddingSize = outputTensor.shape[1];
      }
    } catch (e) {
      print('Model load failed: $e');
    }
  }

  /// Generate L2-normalized face embedding
  static Future<FaceEmbeddingResult> generateEmbedding(img.Image face) async {
    if (_interpreter == null) {
      return FaceEmbeddingResult(
        embedding: _generateDummyEmbedding(),
        isValid: false,
        errorMessage: 'Model not loaded',
      );
    }

    try {
      // Resize to correct size with better padding
      final resized = img.copyResize(face, width: inputSize, height: inputSize);

      // Preprocess
      final input = _preprocessFace(resized);
      final output = List.generate(
        1,
        (_) => List.generate(_embeddingSize, (_) => 0.0, growable: false),
        growable: false,
      );

      // Inference
      _interpreter!.run(input, output);

      // L2 normalize the output
      final embedding = _l2Normalize(output[0].toList());

      return FaceEmbeddingResult(
        embedding: embedding,
        isValid: true,
      );
    } catch (e) {
      return FaceEmbeddingResult(
        embedding: _generateDummyEmbedding(),
        isValid: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Preprocess face image to model input format
  static List<List<List<List<double>>>> _preprocessFace(img.Image face) {
    return List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = face.getPixel(x, y);
            // Normalize to [-1, 1]
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

  /// L2 normalization - makes vector unit length
  static List<double> _l2Normalize(List<double> embedding) {
    double sumSquares = 0.0;
    for (final val in embedding) {
      sumSquares += val * val;
    }
    final magnitude = math.sqrt(sumSquares);

    if (magnitude == 0 || magnitude.isNaN) {
      return List.filled(_embeddingSize, 0.0);
    }

    return embedding.map((e) => e / magnitude).toList();
  }

  /// Cosine similarity for L2-normalized embeddings
  /// Returns value in [0, 1] where 1 = identical, 0 = opposite
  static double cosineSimilarity(List<double> emb1, List<double> emb2) {
    if (emb1.length != emb2.length) {
      throw ArgumentError('Embedding dimension mismatch');
    }

    double dotProduct = 0.0;
    for (int i = 0; i < emb1.length; i++) {
      dotProduct += emb1[i] * emb2[i];
    }

    // For L2-normalized vectors, cosine similarity = dot product
    // Clamp to [-1, 1] to handle floating point errors
    return dotProduct.clamp(-1.0, 1.0);
  }

  /// Cosine distance = 1 - similarity
  /// Returns value in [0, 2] where 0 = identical, 2 = opposite
  static double cosineDistance(List<double> emb1, List<double> emb2) {
    return 1.0 - cosineSimilarity(emb1, emb2);
  }

  /// Compare face embedding against database
  /// Returns comparison result with detailed metrics
  static FaceComparisonResult compareFace({
    required List<double> queryEmbedding,
    required List<List<double>> databaseEmbeddings,
    required List<String> databaseNames,
    double threshold = 0.6, // Cosine distance threshold
  }) {
    if (databaseEmbeddings.isEmpty) {
      return FaceComparisonResult(
        isMatch: false,
        matchedName: 'Unknown',
        confidence: 0.0,
        similarity: 0.0,
        distance: 999.0,
        allDistances: {},
      );
    }

    double bestDistance = double.infinity;
    double bestSimilarity = -1.0;
    int bestIndex = -1;

    Map<String, double> allDistances = {};

    for (int i = 0; i < databaseEmbeddings.length; i++) {
      final similarity = cosineSimilarity(queryEmbedding, databaseEmbeddings[i]);
      final distance = 1.0 - similarity;

      allDistances[databaseNames[i]] = distance;

      if (distance < bestDistance) {
        bestDistance = distance;
        bestSimilarity = similarity;
        bestIndex = i;
      }
    }

    final isMatch = bestDistance < threshold;
    final matchedName = isMatch && bestIndex >= 0 
        ? databaseNames[bestIndex] 
        : 'Unknown';

    // Confidence: 100% at distance=0, 0% at distance=threshold
    final confidence = isMatch 
        ? ((threshold - bestDistance) / threshold * 100).clamp(0.0, 100.0)
        : 0.0;

    return FaceComparisonResult(
      isMatch: isMatch,
      matchedName: matchedName,
      confidence: confidence,
      similarity: bestSimilarity,
      distance: bestDistance,
      allDistances: allDistances,
    );
  }

  static List<double> _generateDummyEmbedding() {
    return List.filled(_embeddingSize, 0.0);
  }

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Result of embedding generation
class FaceEmbeddingResult {
  final List<double> embedding;
  final bool isValid;
  final String? errorMessage;

  FaceEmbeddingResult({
    required this.embedding,
    required this.isValid,
    this.errorMessage,
  });
}

/// Result of face comparison
class FaceComparisonResult {
  final bool isMatch;
  final String matchedName;
  final double confidence; // 0-100%
  final double similarity; // -1 to 1 (cosine similarity)
  final double distance; // 0 to 2 (cosine distance)
  final Map<String, double> allDistances;

  FaceComparisonResult({
    required this.isMatch,
    required this.matchedName,
    required this.confidence,
    required this.similarity,
    required this.distance,
    required this.allDistances,
  });
}
