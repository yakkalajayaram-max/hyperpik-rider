import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../earnings/earnings_screen.dart';
import '../profile/profile_screen.dart';
import '../work/work_screen.dart';

/// Work, Earnings, Profile: the three things a rider does.
class RiderShell extends StatefulWidget {
  const RiderShell({super.key, required this.rider, required this.onRefresh});
  final Rider rider;
  final VoidCallback onRefresh;

  @override
  State<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<RiderShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        WorkScreen(rider: widget.rider),
        EarningsScreen(active: _tab == 1),
        ProfileScreen(rider: widget.rider, onRefresh: widget.onRefresh),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.two_wheeler_outlined), selectedIcon: Icon(Icons.two_wheeler_rounded), label: 'Work'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Me'),
        ],
      ),
    );
  }
}
