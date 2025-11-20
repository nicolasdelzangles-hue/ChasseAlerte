import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/home_screen.dart';
import '../screens/battue_list_screen.dart';
import '../screens/chat_list_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/battue_charts_screen.dart';
import '../providers/battue_provider.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0; // Accueil par défaut

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages(context);

    // ✅ Sécurité : clamp l’index si jamais il dépasse
    final safeIndex = _currentIndex.clamp(0, pages.length - 1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Image.asset(
            'assets/image/Logo_ChasseAlerte.png',
            height: 32,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() {
          // ✅ Sécurité : ne jamais dépasser le nombre de pages
          _currentIndex = (i < pages.length) ? i : pages.length - 1;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Battues',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
        ],
      ),
    );
  }

  /// Construit les pages (Stats dépend du provider, donc pas de `const` ici)
  List<Widget> _buildPages(BuildContext context) {
    return [
      const HomeScreen(),
      const BattueListScreen(),
      const ChatListScreen(),
      const ProfileScreen(),
      _buildStatsTab(context),
    ];
  }

  /// Onglet Stats : loader, message si vide, ou graphiques
  Widget _buildStatsTab(BuildContext context) {
    final p = context.watch<BattueProvider>();

    if (p.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.battues.isEmpty) {
      return const Center(child: Text('Aucune battue disponible'));
    }

    final b = p.battues.first; // plus tard: ajoute un sélecteur si tu veux
    return BattueChartsScreen(battue: b);
  }
}
