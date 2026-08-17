import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../features/home/home_dashboard_screen.dart';
import '../../features/prayer/prayer_times_screen.dart';
import '../../features/tasbeeh/tasbeeh_screen.dart';
import '../../features/quran/quran_screen.dart';
import '../../features/azkar/azkar_screen.dart';
import '../../features/settings/settings_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static final List<Widget> _screens = [
    const HomeDashboardScreen(),
    const QuranScreen(),
    const AzkarScreen(),
    const PrayerTimesScreen(),
    const TasbeehScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) {
          setState(() {
            _index = i;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.menu_book_outlined),
            activeIcon: const Icon(Icons.menu_book),
            label: l10n.navQuran,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.favorite_outline),
            activeIcon: const Icon(Icons.favorite),
            label: l10n.navAzkar,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.access_time),
            activeIcon: const Icon(Icons.access_time_filled),
            label: l10n.navPrayer,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.fingerprint),
            activeIcon: const Icon(Icons.fingerprint),
            label: l10n.navTasbeeh,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: l10n.navMore,
          ),
        ],
      ),
    );
  }
}
