# SwiftPay - Offline Face-Authenticated School Payment System

A fully offline Flutter application for face-authenticated school payments with bold neobrutalist design.

## ✨ Features

### Student View
- **Face Enrollment**: Capture and register student face with ML-powered liveness detection
- **Balance Display**: Large, bold display of current balance
- **Transaction History**: Timeline view of recent activity
- **Demo Top-up**: Add ₹50 to balance for testing

### Vendor POS View
- **Face Payment**: Accept payments via TensorFlow Lite face authentication
- **Real-time Verification**: Cosine similarity matching with embeddings (threshold: 0.55)
- **Anti-Spoofing**: Laplacian-based liveness detection to prevent photo attacks
- **Transaction Logging**: Automatic recording of all payments
- **Statistics Dashboard**: Live count of enrolled students and transactions

## 🧠 Machine Learning Integration

The app now supports **real TensorFlow Lite models** for production-grade face recognition:

### Current Implementation
- **FaceNet Model**: 112x112 input → 192-d embedding vectors
- **Anti-Spoofing**: 256x256 input → real/fake classification
- **Fallback Mode**: Works without models for demo/testing
- **Laplacian Filter**: Sharpness detection (prevents blurry images)

### Model Support
- ✅ MobileFaceNet (face embeddings)
- ✅ Silent-Face-Anti-Spoofing (liveness)
- ✅ Custom TFLite models (drop-in replacement)
- ✅ Automatic fallback if models unavailable

**See [MODEL_SETUP.md](MODEL_SETUP.md) for detailed model installation instructions.**

## 🚀 Setup Instructions

### Installation

1. **Install dependencies**:
```bash
flutter pub get
```

2. **Run the app**:
```bash
flutter run
```

## 📱 Usage

### For Students

1. **Enroll Face**: Tap "ENROLL FACE" → position face in guide → wait for capture
2. **Check Balance**: View current balance on dashboard
3. **Add Money**: Tap "ADD ₹50" to test transactions

### For Vendors

1. **Switch to Vendor Mode**: Tap mode toggle in app bar
2. **Process Payment**: Enter amount → tap "PAY WITH FACE" → verify student
3. **View Statistics**: See enrolled students and transaction count

## 🎨 Design

Neobrutalist School Tech aesthetic with electric teal (#00F5D4), dark charcoal (#0F0F12), and Manrope typography.

## 📂 Key Files

- `lib/main.dart` - App entry, theme, navigation
- `lib/screens/student_view.dart` - Student dashboard
- `lib/screens/vendor_view.dart` - Vendor POS terminal
- `lib/screens/camera_capture.dart` - Camera UI
- `lib/services/tflite_service.dart` - Face recognition

## 🔒 Privacy

100% offline. All data stays on device. No cloud sync.

---

Built for real students, real schools, real payments.
