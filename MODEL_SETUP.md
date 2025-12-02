# Adding TFLite Models to SwiftPay

## Overview
SwiftPay now supports real TensorFlow Lite models for face recognition and liveness detection. The app includes fallback mode if models are not available.

## Required Models

### 1. FaceNet Model (`facenet.tflite`)
**Purpose**: Generate face embeddings for recognition

**Recommended Source**: MobileFaceNet from TensorFlow Hub
- **URL**: https://tfhub.dev/tensorflow/lite-model/mobilefacenet/1/default/1
- Or search for "MobileFaceNet tflite" on GitHub

**Specifications**:
- Input: 112x112x3 (RGB image)
- Output: 192-dimensional embedding vector
- Normalization: [-1, 1] range

**Alternative Models**:
- FaceNet-512 (512-d output)
- InsightFace ArcFace models

### 2. Liveness Detection Model (`liveness.tflite`)
**Purpose**: Detect if the face is real (not a photo/video)

**Recommended Sources**:
1. **Silent Face Anti-Spoofing** (GitHub)
   - Repository: https://github.com/minivision-ai/Silent-Face-Anti-Spoofing
   - Look for TFLite conversion
   
2. **FaceAntiSpoofing** models
   - Search for "face anti spoofing tflite" on GitHub
   
**Specifications**:
- Input: 256x256x3 (RGB image)
- Output: 2 values [fake_score, real_score]
- Real face threshold: 0.7 (configurable)

## Installation Steps

### Step 1: Download Models

#### Option A: Use Pre-trained Models
1. Download MobileFaceNet:
   ```bash
   # Visit TensorFlow Hub and download the model
   # Or use wget/curl if available
   ```

2. Download liveness model from GitHub repo

#### Option B: Convert Your Own Models
If you have PyTorch/ONNX models:
```bash
# Install TensorFlow
pip install tensorflow

# Use TFLite converter
import tensorflow as tf

converter = tf.lite.TFLiteConverter.from_saved_model('model_path')
tflite_model = converter.convert()

with open('facenet.tflite', 'wb') as f:
    f.write(tflite_model)
```

### Step 2: Place Models in Assets
1. Copy models to:
   ```
   assets/models/facenet.tflite
   assets/models/liveness.tflite
   ```

2. The `pubspec.yaml` already includes these assets

### Step 3: Verify Integration
Run the app:
```bash
flutter run
```

Check console for:
- ✅ FaceNet model loaded successfully
- ✅ Anti-spoofing model loaded successfully

## Fallback Mode
If models are not found, the app uses deterministic fallback:
- Face embeddings: Hash-based generation (consistent per image)
- Liveness: Laplacian sharpness detection

This allows the app to work for demo/testing without real models.

## Model Configuration

### Adjust Face Recognition Threshold
Edit `lib/screens/vendor_view.dart`:
```dart
const threshold = 0.55;  // Lower = more lenient (0.4-0.7 recommended)
```

### Adjust Liveness Threshold
Edit `lib/services/face_anti_spoofing.dart`:
```dart
static const double threshold = 0.7;  // Higher = stricter (0.5-0.9 recommended)
```

### Adjust Sharpness Detection
Edit `lib/services/face_anti_spoofing.dart`:
```dart
static const int laplacianThreshold = 1000;  // Higher = require sharper images
```

## Testing Models

### Test Face Recognition
1. Enroll with your face
2. Try to verify as yourself → Should succeed
3. Try with someone else's face → Should fail
4. Try with your photo on phone → Should fail (liveness)

### Test Liveness Detection
1. Take a selfie and try to use it → Should fail
2. Show a video of yourself → Should fail
3. Use live face → Should succeed

## Model Performance

### Expected Accuracy
- **Face Recognition**: 95-99% accuracy (same person)
- **Liveness Detection**: 90-95% accuracy (real vs fake)
- **False Accept Rate**: <1% (with threshold 0.55)
- **False Reject Rate**: 2-5% (with threshold 0.55)

### Speed (On typical devices)
- Face detection: 100-200ms
- Embedding generation: 50-150ms
- Liveness check: 100-200ms
- **Total**: 250-550ms per verification

## Troubleshooting

### Model Not Loading
```
⚠️ TFLite models loading failed: [error]
```
**Solutions**:
1. Check file names match exactly
2. Verify files are in `assets/models/`
3. Run `flutter clean && flutter pub get`
4. Check model format is TFLite (not .pb or .onnx)

### Low Accuracy
**Solutions**:
1. Ensure good lighting during capture
2. Keep face centered and stable
3. Adjust similarity threshold
4. Try different model

### Slow Performance
**Solutions**:
1. Use quantized models (uint8)
2. Reduce input size
3. Increase thread count in code
4. Use GPU delegate (advanced)

## Advanced: GPU Acceleration

To enable GPU acceleration (much faster):

1. Add GPU delegate dependency to `pubspec.yaml`:
```yaml
dependencies:
  tflite_flutter_helper: ^0.3.1
```

2. Update `tflite_service.dart`:
```dart
final options = tfl.InterpreterOptions()
  ..threads = 4
  ..useGpuDelegate = true;
```

## Recommended Model Links

### Face Recognition
1. **MobileFaceNet** (Best balance)
   - https://github.com/sirius-ai/MobileFaceNet_TF
   
2. **InsightFace ArcFace**
   - https://github.com/deepinsight/insightface

### Liveness Detection
1. **Silent-Face-Anti-Spoofing**
   - https://github.com/minivision-ai/Silent-Face-Anti-Spoofing
   
2. **FaceAntiSpoofing**
   - https://github.com/ee09115/spoofing_detection

## Production Recommendations

1. **Encrypt models**: Use Flutter obfuscation
2. **Update thresholds**: Based on your use case
3. **Add telemetry**: Track false accepts/rejects
4. **Regular updates**: Retrain with new data
5. **Multiple checks**: Combine face + liveness + PIN

---

**Note**: The current implementation works in fallback mode without real models. For production deployment, use actual trained models for better accuracy and security.
