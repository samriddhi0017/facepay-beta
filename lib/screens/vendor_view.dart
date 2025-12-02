import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:confetti/confetti.dart';
import '../models/student.dart';
import '../models/transaction.dart';
import '../services/tflite_service.dart';
import 'camera_capture.dart';

class VendorView extends StatefulWidget {
  const VendorView({super.key});

  @override
  State<VendorView> createState() => _VendorViewState();
}

class _VendorViewState extends State<VendorView> {
  final TextEditingController _amountController = TextEditingController();
  Box<Student>? _studentBox;
  Box<Transaction>? _transactionBox;
  late ConfettiController _confettiController;
  bool _isProcessing = false;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initializeBoxes();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }
  
  Future<void> _initializeBoxes() async {
    _studentBox = await Hive.openBox<Student>('students');
    _transactionBox = await Hive.openBox<Transaction>('transactions');
    setState(() {
      _isLoading = false;
    });
  }
  
  Future<void> _processPayment() async {
    final amountText = _amountController.text.trim();
    
    if (amountText.isEmpty) {
      _showErrorMessage('Please enter an amount');
      return;
    }
    
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showErrorMessage('Please enter a valid amount');
      return;
    }
    
    if (_studentBox == null || _studentBox!.isEmpty) {
      _showErrorMessage('No enrolled students found');
      return;
    }
    
    setState(() => _isProcessing = true);
    
    // Open camera for face verification
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraCaptureScreen(mode: 'verify'),
      ),
    );
    
    setState(() => _isProcessing = false);
    
    if (result != null && result['success'] == true) {
      final embedding = result['embedding'] as List<double>;
      
      // Find matching student
      Student? matchedStudent;
      double bestSimilarity = 0.0;
      const threshold = 0.55;
      
      for (final student in _studentBox!.values) {
        final similarity = TFLiteService.cosineSimilarity(
          embedding,
          student.faceEmbedding,
        );
        
        if (similarity > bestSimilarity && similarity >= threshold) {
          bestSimilarity = similarity;
          matchedStudent = student;
        }
      }
      
      if (matchedStudent == null) {
        _showErrorMessage('Face not recognized');
        return;
      }
      
      if (matchedStudent.balance < amount) {
        _showErrorMessage('Insufficient balance: ₹${matchedStudent.balance.toStringAsFixed(2)}');
        return;
      }
      
      // Process payment
      matchedStudent.balance -= amount;
      await matchedStudent.save();
      
      final transaction = Transaction(
        id: 'TXN${DateTime.now().millisecondsSinceEpoch}',
        studentId: matchedStudent.id,
        amount: amount,
        timestamp: DateTime.now(),
        type: 'payment',
        description: 'Vendor payment',
      );
      
      await _transactionBox!.add(transaction);
      
      _confettiController.play();
      _amountController.clear();
      
      _showPaymentSuccess(matchedStudent, amount, bestSimilarity);
      
    } else if (result != null && result['success'] == false) {
      _showErrorMessage(result['error'] ?? 'Verification failed');
    }
  }
  
  void _showPaymentSuccess(Student student, double amount, double confidence) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F12),
            border: Border.all(color: const Color(0xFF00F5D4), width: 2),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF000000),
                offset: Offset(6, 6),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.check,
                  color: Color(0xFF0F0F12),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'PAYMENT SUCCESSFUL',
                style: TextStyle(
                  color: Color(0xFF00F5D4),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              _buildInfoRow('Student', student.name),
              const SizedBox(height: 12),
              _buildInfoRow('Amount', '₹${amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              _buildInfoRow('New Balance', '₹${student.balance.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              _buildInfoRow('Confidence', '${(confidence * 100).toStringAsFixed(1)}%'),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF00F5D4), width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Material(
                  color: const Color(0xFF00F5D4),
                  borderRadius: BorderRadius.circular(2),
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(2),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'DONE',
                          style: TextStyle(
                            color: Color(0xFF0F0F12),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFFF8F9FA).withOpacity(0.7),
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFF8F9FA),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFF8F9FA),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        backgroundColor: const Color(0xFFFF2E63),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
  
  @override
  void dispose() {
    _amountController.dispose();
    _confettiController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F12),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00F5D4),
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      body: Stack(
        children: [
          // Grid Texture Background
          CustomPaint(
            painter: GridBackgroundPainter(),
            child: Container(),
          ),
          
          // Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Text(
                    'VENDOR POS',
                    style: TextStyle(
                      color: Color(0xFF00F5D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Payment Terminal',
                    style: TextStyle(
                      color: Color(0xFFF8F9FA),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Amount Input
                  const Text(
                    'AMOUNT (₹)',
                    style: TextStyle(
                      color: Color(0xFF00F5D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF00F5D4), width: 2),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFF000000),
                          offset: Offset(4, 4),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      style: const TextStyle(
                        color: Color(0xFFF8F9FA),
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(
                          color: Color(0xFFF8F9FA),
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(24),
                      ),
                    ),
                  ),
                  const Spacer(),
                  
                  // Pay Button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF00F5D4), width: 2),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFF000000),
                          offset: Offset(6, 6),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Material(
                      color: const Color(0xFF00F5D4),
                      borderRadius: BorderRadius.circular(2),
                      child: InkWell(
                        onTap: _isProcessing ? null : _processPayment,
                        borderRadius: BorderRadius.circular(2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: _isProcessing
                              ? const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF0F0F12),
                                      strokeWidth: 3,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.face,
                                      color: Color(0xFF0F0F12),
                                      size: 32,
                                    ),
                                    SizedBox(width: 16),
                                    Text(
                                      'PAY WITH FACE',
                                      style: TextStyle(
                                        color: Color(0xFF0F0F12),
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Stats
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFF8F9FA).withOpacity(0.2),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat(
                          'ENROLLED',
                          (_studentBox?.length ?? 0).toString(),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: const Color(0xFFF8F9FA).withOpacity(0.2),
                        ),
                        _buildStat(
                          'TRANSACTIONS',
                          (_transactionBox?.length ?? 0).toString(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              colors: const [
                Color(0xFF00F5D4),
                Color(0xFFF8F9FA),
              ],
              numberOfParticles: 50,
              gravity: 0.3,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF00F5D4),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFFF8F9FA).withOpacity(0.6),
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class GridBackgroundPainter extends CustomPainter {
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
