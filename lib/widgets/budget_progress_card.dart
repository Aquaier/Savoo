import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/iconography.dart';

/// Pokazuje zwięzłą kartę z informacjami o budżecie i paskiem postępu.
class BudgetProgressCard extends StatelessWidget {
  const BudgetProgressCard({super.key, required this.budget, this.onTap});

  final BudgetItem budget;
  final VoidCallback? onTap;

  static const Map<String, String> _budgetTypeLabels = {
    'household': 'Budżet domowy',
    'entertainment': 'Rozrywka',
    'groceries': 'Zakupy',
    'travel': 'Podróże',
    'savings': 'Oszczędności',
    'health': 'Zdrowie',
    'education': 'Edukacja',
    'custom': 'Własny budżet',
  };

  static const Map<String, String> _periodLabels = {
    'weekly': 'Tygodniowy',
    'monthly': 'Miesięczny',
    'quarterly': 'Kwartalny',
    'custom': 'Niestandardowy',
  };

  String _formatBudgetTypeLabel(String value) {
    final label = _budgetTypeLabels[value];
    if (label != null) {
      return label;
    }
    if (value.trim().isEmpty) {
      return 'Budżet';
    }
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  /// Renderuje kartę budżetu z ikoną, opisem i ostrzeżeniami o przekroczeniach.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progressColor = budget.progress > 0.85
        ? Colors.redAccent
        : colorScheme.primary;
    final typeLabel = _formatBudgetTypeLabel(budget.budgetType);
    final periodLabel = _periodLabels[budget.period] ?? budget.period;
    final typeIcon = iconForBudgetType(budget.budgetType);

    final hasCategory = budget.category != null && budget.category!.isNotEmpty;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(typeIcon, size: 22, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      budget.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${budget.spentAmount.toStringAsFixed(0)} ${budget.currency} / ${budget.limitAmount.toStringAsFixed(0)} ${budget.currency}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$typeLabel • $periodLabel',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colorScheme.primary),
                ),
              ),
              if (budget.transactionCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Powiązane transakcje: ${budget.transactionCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (hasCategory)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    budget.category!,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: budget.progress,
                  minHeight: 10,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                budget.remaining >= 0
                    ? 'Pozostało ${budget.remaining.toStringAsFixed(0)} ${budget.currency}'
                    : 'Przekroczenie o ${(budget.remaining.abs()).toStringAsFixed(0)} ${budget.currency}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: progressColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
