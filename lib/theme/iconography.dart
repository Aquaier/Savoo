import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Mapowanie rodzaju transakcji na ikonę wykorzystywaną w UI.
const Map<TransactionKind, IconData> kTransactionKindIcons = {
  TransactionKind.general: Icons.layers_outlined,
  TransactionKind.household: Icons.home_outlined,
  TransactionKind.entertainment: Icons.live_tv_outlined,
  TransactionKind.savings: Icons.savings_outlined,
  TransactionKind.travel: Icons.flight_takeoff,
  TransactionKind.education: Icons.school_outlined,
  TransactionKind.health: Icons.health_and_safety_outlined,
  TransactionKind.investment: Icons.trending_up,
  TransactionKind.salary: Icons.work_outline,
  TransactionKind.bonus: Icons.emoji_events_outlined,
  TransactionKind.gift: Icons.card_giftcard,
  TransactionKind.other: Icons.category_outlined,
};

/// Zwraca ikonę pasującą do wybranego rodzaju transakcji.
IconData iconForTransactionKind(TransactionKind kind) {
  return kTransactionKindIcons[kind] ?? Icons.category_outlined;
}

/// Ikony reprezentujące poszczególne typy budżetów.
const Map<String, IconData> kBudgetTypeIcons = {
  'household': Icons.house_outlined,
  'entertainment': Icons.live_tv_outlined,
  'groceries': Icons.shopping_cart_outlined,
  'travel': Icons.flight_takeoff,
  'savings': Icons.savings_outlined,
  'health': Icons.health_and_safety_outlined,
  'education': Icons.school_outlined,
  'custom': Icons.tune_outlined,
};

/// Dobiera ikonę do budżetu na podstawie pola `budgetType`.
IconData iconForBudgetType(String type) {
  return kBudgetTypeIcons[type] ?? Icons.account_balance_wallet_outlined;
}
