// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/discovery_provider.dart';
import 'providers/transfer_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
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
        home: const HomeScreen(),
      ),
    );
  }
}
