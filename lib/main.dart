// lib/main.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/discovery_provider.dart';
import 'providers/transfer_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }
  runApp(const DropixApp());
}

class DropixApp extends StatelessWidget {
  const DropixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DiscoveryProvider()),
        ChangeNotifierProvider(create: (_) => TransferProvider()..initialize()),
      ],
      child: MaterialApp(
        title: 'Dropix',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080C14),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3D7BFF),
            secondary: Color(0xFF00E5C0),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ── Splash Screen ─────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A2744), Color(0xFF0E1A2E)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF3D7BFF).withOpacity(0.25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3D7BFF).withOpacity(0.18),
                        blurRadius: 48,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3D7BFF), Color(0xFF00E5C0)],
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.wifi_tethering_rounded,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // App name
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF3D7BFF), Color(0xFF00E5C0)],
                  ).createShader(bounds),
                  child: const Text(
                    'Dropix',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Drop files. Instantly.',
                  style: TextStyle(
                    color: Color(0xFF3A4460),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
