import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:confetti/confetti.dart';
import '../models/student.dart';
import '../models/transaction.dart';
import 'camera_capture.dart';

class StudentView extends StatefulWidget {
  const StudentView({super.key});

  @override
  State<StudentView> createState() => _StudentViewState();
}

class _StudentViewState extends State<StudentView> {
  Box<Student>? _studentBox;
  Box<Transaction>? _transactionBox;
  Student? _currentStudent;
  late ConfettiController _confettiController;
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
    _loadCurrentStudent();
    setState(() {
      _isLoading = false;
    });
  }
  
  void _loadCurrentStudent() {
    if (_studentBox != null && _studentBox!.isNotEmpty) {
      setState(() {
        _currentStudent = _studentBox!.getAt(0);
      });
    }
  }
  
  Future<void> _enrollFace() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CameraCaptureScreen(mode: 'enroll'),
      ),
    );
    
    if (result != null && result['success'] == true) {
      final embedding = result['embedding'] as List<double>;
      
      // Create or update student
      final student = Student(
        id: 'STU001',
        name: 'John Doe',
        balance: 500.0,
        faceEmbedding: embedding,
        enrolledAt: DateTime.now(),
      );
      
      await _studentBox!.clear();
      await _studentBox!.add(student);
      
      setState(() {
        _currentStudent = student;
      });
      
      _confettiController.play();
      
      if (mounted) {
        _showSuccessMessage('Face enrolled successfully!');
      }
    } else if (result != null && result['success'] == false) {
      if (mounted) {
        _showErrorMessage(result['error'] ?? 'Enrollment failed');
      }
    }
  }
  
  Future<void> _addMoney() async {
    if (_currentStudent == null) {
      _showErrorMessage('Please enroll your face first');
      return;
    }
    
    _currentStudent!.balance += 50.0;
    await _currentStudent!.save();
    
    final transaction = Transaction(
      id: 'TXN${DateTime.now().millisecondsSinceEpoch}',
      studentId: _currentStudent!.id,
      amount: 50.0,
      timestamp: DateTime.now(),
      type: 'topup',
      description: 'Demo top-up',
    );
    
    await _transactionBox!.add(transaction);
    
    setState(() {});
    
    _showSuccessMessage('₹50 added to your balance');
  }
  
  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF0F0F12),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        backgroundColor: const Color(0xFF00F5D4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        margin: const EdgeInsets.all(16),
      ),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Header
                  const Text(
                    'STUDENT WALLET',
                    style: TextStyle(
                      color: Color(0xFF00F5D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentStudent?.name ?? 'Not Enrolled',
                    style: const TextStyle(
                      color: Color(0xFFF8F9FA),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Balance Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F12),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CURRENT BALANCE',
                          style: TextStyle(
                            color: Color(0xFF00F5D4),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '₹${_currentStudent?.balance.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(
                            color: Color(0xFFF8F9FA),
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Action Buttons
                  if (_currentStudent == null)
                    _buildActionButton(
                      'ENROLL FACE',
                      const Color(0xFF00F5D4),
                      Icons.face,
                      _enrollFace,
                    )
                  else
                    _buildActionButton(
                      'ADD ₹50',
                      const Color(0xFF00F5D4),
                      Icons.add,
                      _addMoney,
                    ),
                  
                  const SizedBox(height: 32),
                  
                  // Recent Transactions
                  const Text(
                    'RECENT ACTIVITY',
                    style: TextStyle(
                      color: Color(0xFF00F5D4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ValueListenableBuilder(
                    valueListenable: _transactionBox!.listenable(),
                    builder: (context, Box<Transaction> box, _) {
                      if (_currentStudent == null) {
                        return _buildEmptyState();
                      }
                      
                      final transactions = box.values
                          .where((t) => t.studentId == _currentStudent!.id)
                          .toList()
                          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
                      
                      if (transactions.isEmpty) {
                        return _buildEmptyState();
                      }
                      
                      return Column(
                        children: transactions.take(3).map((transaction) {
                          return _buildTransactionItem(transaction);
                        }).toList(),
                      );
                    },
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
                Color(0xFFFF2E63),
              ],
              numberOfParticles: 30,
              gravity: 0.3,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF000000),
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(2),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFF0F0F12), size: 24),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF0F0F12),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildTransactionItem(Transaction transaction) {
    final isCredit = transaction.type == 'topup';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        border: Border.all(
          color: isCredit ? const Color(0xFF00F5D4) : const Color(0xFFFF2E63),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isCredit ? const Color(0xFF00F5D4) : const Color(0xFFFF2E63),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: const TextStyle(
                    color: Color(0xFFF8F9FA),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(transaction.timestamp),
                  style: TextStyle(
                    color: const Color(0xFFF8F9FA).withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}₹${transaction.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: isCredit ? const Color(0xFF00F5D4) : const Color(0xFFFF2E63),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFF8F9FA).withOpacity(0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          'No transactions yet',
          style: TextStyle(
            color: const Color(0xFFF8F9FA).withOpacity(0.5),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${date.day} ${_getMonthName(date.month)}';
    }
  }
  
  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
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
