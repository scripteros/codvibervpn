import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/vpn_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/config_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VpnProvider()),
      ],
      child: const HermesVpnApp(),
    ),
  );
}

class HermesVpnApp extends StatelessWidget {
  const HermesVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6C5CE7),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        fontFamily: 'Inter',
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C5CE7),
          secondary: const Color(0xFF00D2FF),
          surface: const Color(0xFF1A1A2E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F1A),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/clients': (context) => const ClientsScreen(),
        '/config': (context) => const ConfigScreen(),
      },
    );
  }
}
