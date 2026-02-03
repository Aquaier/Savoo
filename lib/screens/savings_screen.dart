import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  /// Tworzy widok oszczędności, w którym można przeglądać i dodawać cele.
  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  /// Renderuje listę celów oszczędnościowych z podsumowaniem i akcjami.
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final goals = appState.savingsGoals;
        final currency = appState.user?.defaultCurrency ?? 'PLN';
        final totalSaved = goals.fold<double>(
          0,
          (sum, goal) => sum + goal.currentAmount,
        );
        final totalTarget = goals.fold<double>(
          0,
          (sum, goal) => sum + goal.targetAmount,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Oszczędności',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab-savings',
            onPressed: () => _showCreateGoalSheet(appState),
            icon: const Icon(Icons.add),
            label: const Text('Nowy cel'),
          ),
          body: RefreshIndicator(
            onRefresh: appState.refreshDashboard,
            child: goals.isEmpty
                ? _EmptySavingsState(
                    onCreateTap: () => _showCreateGoalSheet(appState),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      _SavingsSummaryCard(
                        totalSaved: totalSaved,
                        totalTarget: totalTarget,
                        currency: currency,
                      ),
                      const SizedBox(height: 20),
                      ...goals.map(
                        (goal) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _SavingsGoalCard(
                            goal: goal,
                            currency: currency,
                            onContribute: () =>
                                _showContributionSheet(appState, goal),
                            onDelete: () => _confirmDeleteGoal(appState, goal),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// Wyświetla dolny arkusz pozwalający stworzyć nowy cel oszczędnościowy.
  Future<void> _showCreateGoalSheet(AppState appState) async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final currentController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? deadline;
    bool submitting = false;

    /// Pozwala wybrać termin zakończenia celu i zapisuje go
    Future<void> pickDeadline(StateSetter setModalState) async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: deadline ?? now,
        firstDate: now,
        lastDate: DateTime(now.year + 5),
      );
      if (picked != null) {
        setModalState(() => deadline = picked);
      }
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nowy cel oszczędnościowy',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa celu',
                        prefixIcon: Icon(Icons.savings_outlined),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Podaj nazwę celu.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: targetController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Kwota docelowa',
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                      validator: (value) {
                        final sanitized = (value ?? '').replaceAll(',', '.');
                        final amount = double.tryParse(sanitized);
                        if (amount == null || amount <= 0) {
                          return 'Podaj dodatnią kwotę.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: currentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Już odłożone (opcjonalnie)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => pickDeadline(setModalState),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        deadline == null
                            ? 'Dodaj termin'
                            : "Termin: ${DateFormat('dd.MM.yyyy').format(deadline!)}",
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) {
                                return;
                              }
                              final target = double.parse(
                                targetController.text
                                    .replaceAll(',', '.')
                                    .trim(),
                              );
                              final initial =
                                  double.tryParse(
                                    currentController.text
                                        .replaceAll(',', '.')
                                        .trim(),
                                  ) ??
                                  0;
                              setModalState(() => submitting = true);
                              final success = await appState.createSavingsGoal(
                                name: nameController.text.trim(),
                                targetAmount: target,
                                initialAmount: initial,
                                deadline: deadline,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              setModalState(() => submitting = false);
                              if (success) {
                                Navigator.of(context).pop(true);
                              } else {
                                final message =
                                    appState.dataError ??
                                    'Nie udało się utworzyć celu.';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Zapisz cel'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    nameController.dispose();
    targetController.dispose();
    currentController.dispose();

    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cel został dodany.')));
    }
  }

  /// Pokazuje formularz dodania wpłaty do wskazanego celu.
  Future<void> _showContributionSheet(
    AppState appState,
    SavingsGoalItem goal,
  ) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool submitting = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dodaj wpłatę do "${goal.name}"',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Kwota wpłaty',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        final sanitized = (value ?? '').replaceAll(',', '.');
                        final amount = double.tryParse(sanitized);
                        if (amount == null || amount <= 0) {
                          return 'Podaj dodatnią kwotę.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Notatka (opcjonalnie)',
                        prefixIcon: Icon(Icons.sticky_note_2_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) {
                                return;
                              }
                              final amount = double.parse(
                                amountController.text
                                    .replaceAll(',', '.')
                                    .trim(),
                              );
                              setModalState(() => submitting = true);
                              final success = await appState
                                  .addSavingsContribution(
                                    goalId: goal.id,
                                    amount: amount,
                                    note: noteController.text.trim().isEmpty
                                        ? null
                                        : noteController.text.trim(),
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              setModalState(() => submitting = false);
                              if (success) {
                                Navigator.of(context).pop(true);
                              } else {
                                final message =
                                    appState.dataError ??
                                    'Nie udało się dodać wpłaty.';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Dodaj wpłatę'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    amountController.dispose();
    noteController.dispose();

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dodano wpłatę do "${goal.name}".')),
      );
    }
  }

  Future<void> _confirmDeleteGoal(
    AppState appState,
    SavingsGoalItem goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Usuń cel'),
          content: Text(
            'Czy na pewno chcesz usunąć cel "${goal.name}"? Tej operacji nie można cofnąć.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Anuluj'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Usuń'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final success = await appState.deleteSavingsGoal(goal.id);
    if (!mounted) {
      return;
    }

    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cel został usunięty.')));
    } else {
      final message = appState.dataError ?? 'Nie udało się usunąć celu.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Pokazuje ogólne podsumowanie wszystkich celów oszczędnościowych.
class _SavingsSummaryCard extends StatelessWidget {
  const _SavingsSummaryCard({
    required this.totalSaved,
    required this.totalTarget,
    required this.currency,
  });

  final double totalSaved;
  final double totalTarget;
  final String currency;

  /// Buduje kartę z sumarycznymi kwotami i paskiem postępu celów.
  @override
  Widget build(BuildContext context) {
    final progress = totalTarget <= 0
        ? 0.0
        : (totalSaved / totalTarget).clamp(0.0, 1.0).toDouble();
    final formatter = NumberFormat.decimalPattern('pl_PL');
    String formatAmount(double value) {
      return '${formatter.format(value.round())} $currency';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Łącznie odłożone',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            formatAmount(totalSaved),
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 8),
          Text('Cel łączny: ${formatAmount(totalTarget)}'),
        ],
      ),
    );
  }
}

/// Prezentuje szczegóły pojedynczego celu oszczędnościowego wraz z akcją wpłaty.
class _SavingsGoalCard extends StatelessWidget {
  const _SavingsGoalCard({
    required this.goal,
    required this.currency,
    required this.onContribute,
    required this.onDelete,
  });

  final SavingsGoalItem goal;
  final String currency;
  final VoidCallback onContribute;
  final VoidCallback onDelete;

  /// Buduje kartę celu z informacją o statusie, progresie i pozostałej kwocie.
  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.decimalPattern('pl_PL');
    String formatAmount(double value) {
      return '${formatter.format(value.round())} $currency';
    }

    final daysLeft = goal.deadline?.difference(DateTime.now()).inDays;
    final remainingLabel = formatAmount(goal.remainingAmount);
    final targetLabel = formatAmount(goal.targetAmount);
    final savedLabel = formatAmount(goal.currentAmount);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Usuń cel',
                icon: const Icon(Icons.delete_outline),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color:
                      (goal.isActive
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline)
                          .withValues(alpha: 0.12),
                ),
                child: Text(
                  goal.isActive ? 'Aktywny' : 'Zakończony',
                  style: TextStyle(
                    color: goal.isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$savedLabel / $targetLabel',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: goal.progress,
            minHeight: 8,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pozostało: $remainingLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (daysLeft != null)
                Row(
                  children: [
                    const Icon(Icons.timelapse, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      daysLeft >= 0 ? '$daysLeft dni do celu' : 'Termin minął',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onContribute,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Dodaj wpłatę'),
          ),
        ],
      ),
    );
  }
}

/// Informuje użytkownika, że nie ma jeszcze celów i zachęca do utworzenia pierwszego.
class _EmptySavingsState extends StatelessWidget {
  const _EmptySavingsState({required this.onCreateTap});

  final VoidCallback onCreateTap;

  /// Buduje ekran pustego stanu z przyciskiem do dodania nowego celu.
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      children: [
        Icon(
          Icons.savings_outlined,
          size: 96,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'Brak celów oszczędnościowych',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Dodaj pierwszy cel, aby śledzić postępy oszczędzania i szybciej realizować plany.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCreateTap,
          icon: const Icon(Icons.add),
          label: const Text('Utwórz cel'),
        ),
      ],
    );
  }
}
