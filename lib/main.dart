import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/student.dart';
import 'models/transaction.dart';
import 'services/tflite_service.dart';
import 'screens/student_view.dart';
import 'screens/vendor_view.dart';
import 'screens/debug_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await Hive.initFlutter();
  
  // Register adapters
  Hive.registerAdapter(StudentAdapter());
  Hive.registerAdapter(TransactionAdapter());
  
  // Initialize TFLite
  await TFLiteService.initialize();
  
  // Set system UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F0F12),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftPay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFFF8F9FA),
          error: Color(0xFFFF2E63),
          surface: Color(0xFF0F0F12),
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          ThemeData.dark().textTheme,
        ).apply(
          bodyColor: const Color(0xFFF8F9FA),
          displayColor: const Color(0xFFF8F9FA),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isVendorMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F12),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 4,
              height: 24,
              color: const Color(0xFF00F5D4),
            ),
            const SizedBox(width: 12),
            const Text(
              'SWIFTPAY',
              style: TextStyle(
                color: Color(0xFFF8F9FA),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isVendorMode ? const Color(0xFF00F5D4) : const Color(0xFFF8F9FA).withOpacity(0.3),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Material(
              color: _isVendorMode ? const Color(0xFF00F5D4) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isVendorMode = !_isVendorMode;
                  });
                },
                borderRadius: BorderRadius.circular(2),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _isVendorMode ? Icons.store : Icons.person,
                        color: _isVendorMode ? const Color(0xFF0F0F12) : const Color(0xFFF8F9FA),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isVendorMode ? 'VENDOR' : 'STUDENT',
                        style: TextStyle(
                          color: _isVendorMode ? const Color(0xFF0F0F12) : const Color(0xFFF8F9FA),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isVendorMode
            ? const VendorView(key: ValueKey('vendor'))
            : const StudentView(key: ValueKey('student')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DebugView()),
          );
        },
        backgroundColor: const Color(0xFF00F5D4),
        child: const Icon(
          Icons.bug_report,
          color: Color(0xFF0F0F12),
        ),
      ),
    );
  }
}
