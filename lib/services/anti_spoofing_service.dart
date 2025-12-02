import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class AntiSpoofingService {
  static const String modelFile = "assets/models/liveness.tflite";
  static const int inputImageSize = 256;
  static const double threshold = 0.7;
  static const int laplaceThreshold = 50;
  static const int laplacianThreshold = 1000;
  
  static tfl.Interpreter? _interpreter;

  static Future<void> initialize() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset(modelFile);
      print('✅ Anti-spoofing model loaded successfully');
    } catch (e) {
      print('⚠️ Anti-spoofing model loading failed: $e');
      print('Using fallback liveness detection');
    }
  }

  static Future<bool> checkLiveness(imglib.Image face) async {
    if (_interpreter == null) {
      // Fallback: Basic sharpness check
      return _checkSharpness(face);
    }

    try {
      // Check image sharpness first
      final laplacianScore = _calculateLaplacian(face);
      if (laplacianScore < laplacianThreshold) {
        print('⚠️ Image too blurry: $laplacianScore');
        return false;
      }

      // Resize face to model input size
      final resized = imglib.copyResize(face, width: inputImageSize, height: inputImageSize);
      
      // Normalize image
      final input = _normalizeImage(resized);
      
      // Prepare output buffers
      final output = List.filled(1, List.filled(2, 0.0));
      
      // Run inference
      _interpreter!.run([input], output);
      
      // Output: [fake_score, real_score]
      final realScore = output[0][1];
      
      print('🔍 Liveness score: $realScore (threshold: $threshold)');
      
      return realScore >= threshold;
      
    } catch (e) {
      print('⚠️ Liveness detection error: $e');
      return _checkSharpness(face);
    }
  }

  static bool _checkSharpness(imglib.Image face) {
    final laplacianScore = _calculateLaplacian(face);
    return laplacianScore >= laplacianThreshold;
  }

  static List<List<List<List<double>>>> _normalizeImage(imglib.Image image) {
    final h = image.height;
    final w = image.width;
    const imageStd = 128.0;

    return List.generate(
      1,
      (_) => List.generate(
        h,
        (i) => List.generate(
          w,
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
    // Resize for faster computation
    final resized = imglib.copyResize(bitmap, width: inputImageSize, height: inputImageSize);
    
    const laplace = [
      [0, 1, 0],
      [1, -4, 1],
      [0, 1, 0]
    ];
    
    const size = 3;
    final grayscale = imglib.grayscale(resized);
    final height = grayscale.height;
    final width = grayscale.width;

    int score = 0;
    
    for (int x = 0; x < height - size + 1; x++) {
      for (int y = 0; y < width - size + 1; y++) {
        int result = 0;
        
        // Convolution operation
        for (int i = 0; i < size; i++) {
          for (int j = 0; j < size; j++) {
            final pixel = grayscale.getPixel(x + i, y + j);
            result += (pixel.r.toInt()) * laplace[i][j];
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
    _interpreter = null;
  }
}
