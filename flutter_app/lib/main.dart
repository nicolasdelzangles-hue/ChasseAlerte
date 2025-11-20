import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'providers/auth_provider.dart';
import 'providers/battue_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/network_status_provider.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/RegisterScreen.dart'; // écran d'inscription
import '../main_navigation.dart'; // <- si tu l'utilises vraiment, sinon tu peux supprimer l'import
import 'screens/add_battue_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Init Hive + ouverture des box AVANT d'utiliser AuthProvider
  await Hive.initFlutter();
  await Hive.openBox('battuesBox');
  await Hive.openBox('favoritesBox');
  await Hive.openBox('sessionBox'); // token, userId, etc.

  // 2) Préparation AuthProvider pour l’auto-login
  final auth = AuthProvider();
  await auth.tryAutoLogin();

  // 3) Lancement de l'appli avec tous les providers
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<NetworkStatusProvider>(
          create: (_) => NetworkStatusProvider(),
        ),
        ChangeNotifierProvider<BattueProvider>(
          create: (_) => BattueProvider(),
        ),
        ChangeNotifierProvider<ChatProvider>(
          create: (_) =>
              ChatProvider(apiBase: 'http://localhost:3000')..init(),
        ),
      ],
      child: const ChasseAlerteApp(),
    ),
  );
}

class ChasseAlerteApp extends StatelessWidget {
  const ChasseAlerteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return MaterialApp(
      title: 'ChasseAlerte',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // tu pourras plugger ton thème dark/light ici
      ),

      // Si tu as une nav à onglets globale, tu pourras remplacer par MainNavigation()
      home: auth.isAuthenticated ? const HomeScreen() : const LoginScreen(),

      routes: {
        '/login':    (_) => const LoginScreen(),
        '/home':     (_) => const HomeScreen(),
        '/register': (_) => const RegisterScreen(),
        // '/tabs': (_) => const MainNavigation(),
        // '/battues/add': (_) => const AddBattueScreen(),
      },
    );
  }
}
