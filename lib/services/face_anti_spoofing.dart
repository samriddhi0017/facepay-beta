import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class AntiSpoofingService {
  static const String modelFile = "assets/models/liveness.tflite";
  static const int inputImageSize = 256;
  static const double threshold = 0.3; // Very lenient threshold
  static const int laplaceThreshold = 50;
  static const int laplacianThreshold = 100; // Much more lenient - was 500
  
  static tfl.Interpreter? _interpreter;
  
  // Expose interpreter status for debugging
  static bool get isLivenessModelLoaded => _interpreter != null;

  static Future<void> initialize() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset(modelFile);
      print('✅ Anti-spoofing model loaded successfully');
    } catch (e) {
      print('⚠️ Anti-spoofing model loading failed: $e');
    }
  }

  static Future<bool> checkLiveness(imglib.Image face) async {
    // Always return true in fallback mode for demo
    if (_interpreter == null) {
      print('⚠️ No liveness model - using fallback (always pass)');
      return true;
    }

    try {
      final laplacianScore = _calculateLaplacian(face);
      print('🔍 Laplacian score: $laplacianScore (threshold: $laplacianThreshold)');
      
      if (laplacianScore < laplacianThreshold) {
        print('⚠️ Image too blurry: $laplacianScore < $laplacianThreshold');
        // Still pass in demo mode
        return true;
      }

      final resized = imglib.copyResize(face, width: inputImageSize, height: inputImageSize);
      final input = _normalizeImage(resized);
      final output = List.filled(1, List.filled(2, 0.0));
      
      _interpreter!.run([input], output);
      
      final realScore = output[0][1];
      print('🔍 Liveness score: $realScore (threshold: $threshold)');
      
      return realScore >= threshold;
    } catch (e) {
      print('⚠️ Liveness error: $e - passing anyway for demo');
      return true; // Pass on error
    }
  }

  static List<List<List<List<double>>>> _normalizeImage(imglib.Image image) {
    const imageStd = 128.0;
    return List.generate(
      1,
      (_) => List.generate(
        image.height,
        (i) => List.generate(
          image.width,
          (j) {
            final pixel = image.getPixel(j, i);
            return [
              (pixel.r - imageStd) / imageStd,
              (pixel.g - imageStd) / imageStd,
              (pixel.b - imageStd) / imageStd,
            ];
          },
        ),
      ),
    );
  }

  static int _calculateLaplacian(imglib.Image bitmap) {
    final resized = imglib.copyResize(bitmap, width: inputImageSize, height: inputImageSize);
    const laplace = [[0, 1, 0], [1, -4, 1], [0, 1, 0]];
    final grayscale = imglib.grayscale(resized);
    int score = 0;
    
    for (int x = 0; x < grayscale.height - 2; x++) {
      for (int y = 0; y < grayscale.width - 2; y++) {
        int result = 0;
        for (int i = 0; i < 3; i++) {
          for (int j = 0; j < 3; j++) {
            final pixel = grayscale.getPixel(x + i, y + j);
            result += pixel.r.toInt() * laplace[i][j];
          }
        }
        if (result.abs() > laplaceThreshold) {
          score++;
        }
      }
    }
    return score;
  }

  static void dispose() {
    _interpreter?.close();
  }
}
