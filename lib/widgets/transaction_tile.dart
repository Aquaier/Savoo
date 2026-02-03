import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/iconography.dart';

/// Wyświetla pojedynczą transakcję z ikoną, metadanymi i kwotą.
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction});

  final TransactionItem transaction;

  /// Renderuje kartę transakcji, kolorując ją zależnie od typu.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = transaction.type == TransactionType.expense;
    final isIncome = transaction.type == TransactionType.income;
    final color = isIncome
        ? Colors.teal
        : isExpense
        ? Colors.redAccent
        : Colors.indigo;
    final appState = context.read<AppState>();
    final kindLabel = appState.transactionKindLabel(transaction.kind);
    final metaParts = <String>[
      transaction.category,
      if (transaction.kind != TransactionKind.general) kindLabel,
      _formatDate(transaction.occurredOn),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(iconForTransactionKind(transaction.kind), color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metaParts.where((part) => part.isNotEmpty).join(' • '),
                  style: theme.textTheme.bodySmall,
                ),
                if (transaction.budgetName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Budżet: ${transaction.budgetName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (transaction.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      transaction.note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _formatAmount(transaction.amount, transaction.currency, isExpense),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Formatuje kwotę z odpowiednim znakiem i walutą.
  String _formatAmount(double value, String currency, bool isExpense) {
    final sign = isExpense ? '-' : '+';
    return '$sign${value.toStringAsFixed(0)} $currency';
  }

  /// Zwraca skróconą datę w układzie dd.MM.
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }
}
