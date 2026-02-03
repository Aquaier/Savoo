import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'transactions_screen.dart';
import 'savings_screen.dart';
import 'budgets_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Tworzy stan nawigacji dolnej, przełączającej między głównymi widokami.
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  /// Renderuje główny szkielet ekranu z `IndexedStack` i dolnym paskiem nawigacji.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          DashboardScreen(key: ValueKey('dashboard')),
          TransactionsScreen(key: ValueKey('transactions')),
          SavingsScreen(key: ValueKey('savings')),
          BudgetsScreen(key: ValueKey('budgets')),
          ProfileScreen(key: ValueKey('profile')),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              height: 1.1,
              letterSpacing: -0.2,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith(
            (_) => const IconThemeData(size: 22),
          ),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          indicatorColor: Colors.transparent,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Pulpit',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transakcje',
            ),
            NavigationDestination(
              icon: Icon(Icons.savings_outlined),
              selectedIcon: Icon(Icons.savings),
              label: 'Oszczędności',
            ),
            NavigationDestination(
              icon: Icon(Icons.pie_chart_outline),
              selectedIcon: Icon(Icons.pie_chart),
              label: 'Budżety',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }
}
