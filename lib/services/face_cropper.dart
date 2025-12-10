import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceCropper {
  /// Crop face from camera image with proper padding
  /// Padding is 30% of face dimensions for better context
  static Future<img.Image> cropFaceFromCamera(
    CameraImage cameraImage,
    Face face, {
    double paddingPercent = 0.3, // 30% padding
  }) async {
    final width = cameraImage.width;
    final height = cameraImage.height;

    // Convert NV21/YUV to RGB
    final rgbImage = await _convertToRGB(cameraImage);

    // Calculate padding in pixels
    final box = face.boundingBox;
    final faceWidth = box.width;
    final faceHeight = box.height;

    final paddingX = (faceWidth * paddingPercent).toInt();
    final paddingY = (faceHeight * paddingPercent).toInt();

    // Apply padding with bounds checking
    final left = (box.left - paddingX).clamp(0, width - 1).toInt();
    final top = (box.top - paddingY).clamp(0, height - 1).toInt();
    final right = (box.right + paddingX).clamp(0, width).toInt();
    final bottom = (box.bottom + paddingY).clamp(0, height).toInt();

    // Ensure valid dimensions
    final cropWidth = (right - left).clamp(1, width);
    final cropHeight = (bottom - top).clamp(1, height);

    return img.copyCrop(
      rgbImage,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  /// Convert camera YUV/NV21 image to RGB
  static Future<img.Image> _convertToRGB(CameraImage cameraImage) async {
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    final rgbImage = img.Image(width: width, height: height);

    final yPlane = cameraImage.planes[0].bytes;
    final yRowStride = cameraImage.planes[0].bytesPerRow;

    // Check for UV plane (color image)
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

          rgbImage.setPixelRgb(x, y, r, g, b);
        }
      }
    } else {
      // Grayscale fallback
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yRowStride + x;
          if (yIndex >= yPlane.length) continue;
          final yValue = yPlane[yIndex];
          rgbImage.setPixelRgb(x, y, yValue, yValue, yValue);
        }
      }
    }

    return rgbImage;
  }
}
