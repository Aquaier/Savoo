import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/transaction_tile.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  /// Pokazuje listę transakcji wraz z akcjami odświeżania i dodawania nowych wpisów.
  @override
  Widget build(BuildContext context) {
    final transactions = context.select<AppState, List<TransactionItem>>(
      (state) => state.transactions,
    );
    final defaultCurrency = context.select<AppState, String>(
      (state) => state.user?.defaultCurrency ?? 'PLN',
    );
    final isLoading = context.select<AppState, bool>(
      (state) => state.isLoading,
    );
    final appState = context.read<AppState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Twoje transakcje',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            return TransactionTile(transaction: transactions[index]);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-transactions',
        onPressed: isLoading
            ? null
            : () async {
                final newTransaction = await _showAddTransactionSheet(
                  context,
                  defaultCurrency,
                );
                if (newTransaction != null) {
                  final success = await appState.addTransaction(newTransaction);
                  if (!context.mounted) {
                    return;
                  }
                  if (!success) {
                    final message =
                        appState.dataError ??
                        'Nie udało się zapisać transakcji.';
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(message)));
                  }
                }
              },
        icon: const Icon(Icons.add),
        label: const Text('Dodaj transakcję'),
      ),
    );
  }

  /// Wyświetla dolny arkusz tworzenia transakcji i zwraca obiekt po wypełnieniu.
  Future<TransactionItem?> _showAddTransactionSheet(
    BuildContext context,
    String defaultCurrency,
  ) async {
    return showModalBottomSheet<TransactionItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _AddTransactionSheet(defaultCurrency: defaultCurrency),
    );
  }
}

/// Formularz do wprowadzania szczegółów nowej transakcji.
class _AddTransactionSheet extends StatefulWidget {
  const _AddTransactionSheet({required this.defaultCurrency});

  final String defaultCurrency;

  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final _formKey = GlobalKey<FormState>();

  TransactionType _selectedType = TransactionType.expense;
  final TransactionKind _selectedKind = TransactionKind.general;
  late String _selectedCurrency;
  int? _selectedCategoryId;
  int? _selectedBudgetId;

  static const List<String> _currencies = ['PLN', 'EUR', 'USD', 'GBP'];
  static const Map<String, String> _budgetTypeLabels = {
    'household': 'Domowy',
    'entertainment': 'Rozrywka',
    'groceries': 'Zakupy',
    'travel': 'Podróże',
    'savings': 'Oszczędności',
    'health': 'Zdrowie',
    'education': 'Edukacja',
    'custom': 'Własny',
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

  /// Ustawia kontrolery oraz domyślne wartości pól po otwarciu arkusza.
  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _amountController = TextEditingController();
    _noteController = TextEditingController();
    _selectedCurrency = widget.defaultCurrency;
    _selectedCategoryId = null;
    _selectedBudgetId = null;
    if (_selectedType == TransactionType.expense) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final expenseCategories = context
            .read<AppState>()
            .categories
            .where((category) => category.type == TransactionType.expense)
            .toList();
        if (expenseCategories.isNotEmpty) {
          setState(() => _selectedCategoryId = expenseCategories.first.id);
        }
      });
    }
  }

  /// Sprząta kontrolery tekstowe, gdy arkusz znika z ekranu.
  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Buduje formularz dodawania transakcji z dynamicznymi polami dla wydatków i wpływów.
  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final categories = context.select<AppState, List<CategoryItem>>(
      (state) => state.categories,
    );
    final expenseCategories =
        categories
            .where((category) => category.type == TransactionType.expense)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final budgets = context.select<AppState, List<BudgetItem>>(
      (state) => state.budgets,
    );
    final expenseBudgets = [...budgets]
      ..sort((a, b) => a.name.compareTo(b.name));
    final isExpense = _selectedType == TransactionType.expense;
    final selectedCategoryId = _selectedCategoryId;
    final canSubmit =
        !isExpense || expenseCategories.isNotEmpty || expenseBudgets.isNotEmpty;

    if (isExpense) {
      final hasSelection =
          selectedCategoryId != null &&
          expenseCategories.any(
            (category) => category.id == selectedCategoryId,
          );
      if (!hasSelection && expenseCategories.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedCategoryId = expenseCategories.first.id);
        });
      } else if (expenseCategories.isEmpty && selectedCategoryId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedCategoryId = null);
        });
      }
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(24, 24, 24, viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dodaj transakcję',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Wydatek'),
                    icon: Icon(Icons.call_received_rounded),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Zasilenie'),
                    icon: Icon(Icons.call_made_rounded),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (selection) =>
                    _onTypeChanged(selection.first),
              ),
              const SizedBox(height: 12),
              if (isExpense)
                Column(
                  children: [
                    if (expenseCategories.isNotEmpty)
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Kategoria',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        initialValue: selectedCategoryId,
                        items: expenseCategories
                            .map(
                              (category) => DropdownMenuItem<int>(
                                value: category.id,
                                child: Text(category.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                        validator: (value) {
                          if (_selectedType == TransactionType.expense &&
                              value == null &&
                              expenseBudgets.isEmpty) {
                            return 'Wybierz kategorię lub budżet.';
                          }
                          return null;
                        },
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _openCategoryDeleter,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Usuń kategorię'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _openCategoryCreator,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Nowa kategoria'),
                        ),
                      ],
                    ),
                    if (expenseCategories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Brak kategorii wydatków. Możesz dodać kategorię w ustawieniach lub przypisać wydatek do budżetu.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    if (expenseBudgets.isNotEmpty) ...[
                      DropdownButtonFormField<int?>(
                        decoration: const InputDecoration(
                          labelText: 'Budżet (opcjonalnie)',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        initialValue: _selectedBudgetId,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Bez przypisania'),
                          ),
                          ...expenseBudgets.map(
                            (budget) => DropdownMenuItem<int?>(
                              value: budget.id,
                              child: Text(budget.name),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedBudgetId = value),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (expenseBudgets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Nie masz jeszcze zapisanego budżetu.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                  ],
                )
              else
                const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tytuł',
                  prefixIcon: Icon(Icons.edit_note_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Waluta',
                  prefixIcon: Icon(Icons.currency_exchange),
                ),
                initialValue: _selectedCurrency,
                items: _currencies
                    .map(
                      (currency) => DropdownMenuItem<String>(
                        value: currency,
                        child: Text(currency),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedCurrency = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kwota',
                  prefixIcon: Icon(Icons.numbers),
                ),
                validator: (value) {
                  final text = value?.replaceAll(',', '.').trim();
                  if (text == null || text.isEmpty) {
                    return 'Podaj kwotę.';
                  }
                  final parsed = double.tryParse(text);
                  if (parsed == null || parsed <= 0) {
                    return 'Kwota musi być liczbą dodatnią.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Notatka (opcjonalnie)',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Anuluj'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSubmit ? _submit : null,
                      child: const Text('Dodaj'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Waliduje dane i zamyka arkusz, zwracając utworzoną transakcję do nadrzędnego widoku.
  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedCategory = _selectedType == TransactionType.expense
        ? _categoryById(_selectedCategoryId)
        : null;
    final selectedBudget = _selectedType == TransactionType.expense
        ? _budgetById(_selectedBudgetId)
        : null;
    if (_selectedType == TransactionType.expense &&
        selectedCategory == null &&
        selectedBudget == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wybierz kategorię lub budżet dla wydatku.'),
        ),
      );
      return;
    }

    final parsedAmount = double.parse(
      _amountController.text.replaceAll(',', '.').trim(),
    );
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isEmpty
        ? (_selectedType == TransactionType.expense ? 'Wydatek' : 'Zasilenie')
        : rawTitle;
    final noteText = _noteController.text.trim();
    final categoryName =
        selectedCategory?.name ??
        selectedBudget?.name ??
        (_selectedType == TransactionType.expense ? 'Wydatek' : 'Zasilenie');

    Navigator.of(context).pop(
      TransactionItem(
        title: title,
        category: categoryName,
        amount: parsedAmount,
        type: _selectedType,
        kind: _selectedKind,
        occurredOn: DateTime.now(),
        currency: _selectedCurrency,
        note: noteText.isEmpty ? null : noteText,
        categoryId: selectedCategory?.id,
        budgetId: selectedBudget?.id,
        budgetName: selectedBudget?.name,
      ),
    );
  }

  /// Aktualizuje formularz po zmianie typu transakcji (wydatek/zasilenie).
  void _onTypeChanged(TransactionType newType) {
    if (_selectedType == newType) {
      return;
    }
    setState(() {
      _selectedType = newType;
      _selectedBudgetId = null;
      if (newType == TransactionType.expense) {
        final expenseCategories = context
            .read<AppState>()
            .categories
            .where((category) => category.type == TransactionType.expense)
            .toList();
        _selectedCategoryId = expenseCategories.isNotEmpty
            ? expenseCategories.first.id
            : null;
      } else {
        _selectedCategoryId = null;
      }
    });
  }

  /// Wyszukuje budżet po identyfikatorze, aby podpiąć wydatek do limitu.
  BudgetItem? _budgetById(int? id) {
    if (id == null) {
      return null;
    }
    final budgets = context.read<AppState>().budgets;
    for (final budget in budgets) {
      if (budget.id == id) {
        return budget;
      }
    }
    return null;
  }

  /// Zwraca kategorię wydatków wskazaną w formularzu (jeśli istnieje).
  CategoryItem? _categoryById(int? id) {
    if (id == null) {
      return null;
    }
    final categories = context.read<AppState>().categories;
    for (final category in categories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  /// Uruchamia dialog tworzenia nowej kategorii wydatków
  Future<void> _openCategoryCreator() async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.maybeOf(context);

    final createdCategory = await showDialog<CategoryItem?>(
      context: context,
      builder: (dialogContext) {
        return _CreateExpenseCategoryDialog(
          appState: appState,
          messenger: messenger,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (createdCategory != null) {
      setState(() => _selectedCategoryId = createdCategory.id);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Dodano kategorię "${createdCategory.name}".')),
      );
    }
  }

  Future<void> _openCategoryDeleter() async {
    final appState = context.read<AppState>();
    final expenseCategories =
        appState.categories
            .where((category) => category.type == TransactionType.expense)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    if (expenseCategories.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Brak kategorii do usunięcia.')),
      );
      return;
    }

    final selected = await showDialog<CategoryItem?>(
      context: context,
      builder: (context) =>
          _DeleteExpenseCategoryDialog(categories: expenseCategories),
    );

    if (!mounted || selected == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Potwierdź usunięcie'),
          content: Text(
            'Czy na pewno chcesz usunąć kategorię "${selected.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Nie'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tak'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirm != true) {
      return;
    }

    final success = await appState.deleteCategory(selected.id);
    if (!mounted) {
      return;
    }

    if (success) {
      if (_selectedCategoryId == selected.id) {
        final remaining =
            appState.categories
                .where((category) => category.type == TransactionType.expense)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        setState(
          () => _selectedCategoryId = remaining.isNotEmpty
              ? remaining.first.id
              : null,
        );
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Usunięto kategorię "${selected.name}".')),
      );
    } else {
      final message = appState.dataError ?? 'Nie udało się usunąć kategorii.';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _CreateExpenseCategoryDialog extends StatefulWidget {
  const _CreateExpenseCategoryDialog({required this.appState, this.messenger});

  final AppState appState;
  final ScaffoldMessengerState? messenger;

  @override
  State<_CreateExpenseCategoryDialog> createState() =>
      _CreateExpenseCategoryDialogState();
}

class _DeleteExpenseCategoryDialog extends StatelessWidget {
  const _DeleteExpenseCategoryDialog({required this.categories});

  final List<CategoryItem> categories;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Usuń kategorię'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: categories.length,
          separatorBuilder: (_, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final category = categories[index];
            return ListTile(
              title: Text(category.name),
              onTap: () => Navigator.of(context).pop(category),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zamknij'),
        ),
      ],
    );
  }
}

class _CreateExpenseCategoryDialogState
    extends State<_CreateExpenseCategoryDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _submitting = true);
    final created = await widget.appState.createExpenseCategory(
      _controller.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);

    if (created != null) {
      Navigator.of(context).pop(created);
      return;
    }

    final message =
        widget.appState.dataError ?? 'Nie udało się utworzyć kategorii.';
    widget.messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nowa kategoria wydatku'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nazwa kategorii',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Podaj nazwę kategorii.';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Dodaj'),
        ),
      ],
    );
  }
}
