import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/iconography.dart';
import '../widgets/budget_progress_card.dart';
import 'budget_detail_screen.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  /// Renderuje listę zapisanych budżetów i umożliwia przejście do tworzenia nowego.
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final budgets = appState.budgets;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              'Budżety',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab-budgets',
            onPressed: appState.isLoading
                ? null
                : () => _openCreateBudgetSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Nowy budżet'),
          ),
          body: budgets.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Nie masz jeszcze żadnych budżetów. Dodaj pierwszy, aby śledzić swoje wydatki.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  itemCount: budgets.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: BudgetProgressCard(
                        budget: budgets[index],
                        onTap: () =>
                            _openBudgetDetails(context, budgets[index]),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  /// Przechodzi do ekranu szczegółów konkretnego budżetu.
  void _openBudgetDetails(BuildContext context, BudgetItem budget) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BudgetDetailScreen(budget: budget)),
    );
  }

  /// Otwiera dolny arkusz dodawania budżetu i pokazuje komunikat po sukcesie.
  Future<void> _openCreateBudgetSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CreateBudgetSheet(),
    );
    if (!context.mounted) {
      return;
    }
    if (created == true) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Budżet został dodany.')),
      );
    }
  }
}

class _CreateBudgetSheet extends StatefulWidget {
  const _CreateBudgetSheet();

  /// Tworzy stan kontrolujący formularz nowego budżetu.
  @override
  State<_CreateBudgetSheet> createState() => _CreateBudgetSheetState();
}

class _CreateBudgetSheetState extends State<_CreateBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _limitController = TextEditingController();

  late String _selectedType;
  String _selectedPeriod = 'monthly';
  int? _selectedCategoryId;
  bool _saving = false;

  static const Map<String, String> _budgetTypes = {
    'household': 'Budżet domowy',
    'entertainment': 'Rozrywka',
    'groceries': 'Zakupy',
    'travel': 'Podróże',
    'savings': 'Oszczędności',
    'health': 'Zdrowie',
    'education': 'Edukacja',
  };

  static const Map<String, String> _periods = {
    'weekly': 'Tygodniowy',
    'monthly': 'Miesięczny',
    'quarterly': 'Kwartalny',
  };

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final availableTypes = _availableBudgetTypeKeys(appState);
    _selectedType = availableTypes.isNotEmpty
        ? availableTypes.first
        : _budgetTypes.keys.first;
  }

  String _formatBudgetTypeLabel(String value) {
    final baseLabel = _budgetTypes[value];
    if (baseLabel != null) {
      return baseLabel;
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

  Iterable<MapEntry<String, String>> _visibleDefaultBudgetTypes(
    AppState appState,
  ) {
    return _budgetTypes.entries.where(
      (entry) => !appState.hiddenDefaultBudgetTypes.contains(entry.key),
    );
  }

  List<String> _availableBudgetTypeKeys(AppState appState) {
    return [
      ..._visibleDefaultBudgetTypes(appState).map((entry) => entry.key),
      ...appState.budgetTypes.map((item) => item.name),
    ];
  }

  bool _canDeleteBudgetTypes(AppState appState) {
    return _availableBudgetTypeKeys(appState).length > 1;
  }

  Future<void> _openBudgetTypeCreator() async {
    final appState = context.read<AppState>();
    final controller = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nowy rodzaj budżetu'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nazwa rodzaju',
            prefixIcon: Icon(Icons.style_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    final raw = created?.trim();
    if (raw == null || raw.isEmpty) {
      return;
    }
    final normalized = raw.toLowerCase();
    final existing = {
      ..._budgetTypes.keys,
      ...appState.budgetTypes.map((item) => item.name),
    };
    if (existing.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taki rodzaj budżetu już istnieje.')),
      );
      return;
    }
    final createdType = await appState.createBudgetType(normalized);
    if (!mounted || createdType == null) {
      return;
    }
    setState(() => _selectedType = createdType.name);
  }

  Future<void> _openBudgetTypeDeleter() async {
    final appState = context.read<AppState>();
    if (!_canDeleteBudgetTypes(appState)) {
      return;
    }
    final options = [
      ..._visibleDefaultBudgetTypes(appState).map(
        (entry) => _BudgetTypeDeletionOption(
          name: entry.key,
          label: entry.value,
          isDefault: true,
        ),
      ),
      ...appState.budgetTypes.map(
        (type) => _BudgetTypeDeletionOption(
          name: type.name,
          label: _formatBudgetTypeLabel(type.name),
          id: type.id,
          isDefault: false,
        ),
      ),
    ];
    final selected = await showDialog<_BudgetTypeDeletionOption>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Usuń rodzaj budżetu'),
        children: options
            .map(
              (option) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(option),
                child: Text(option.label),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    final availableTypes = _availableBudgetTypeKeys(appState);
    if (availableTypes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nie możesz usunąć ostatniego rodzaju budżetu.'),
        ),
      );
      return;
    }
    if (selected.isDefault) {
      appState.hideDefaultBudgetType(selected.name);
    } else if (selected.id != null) {
      final success = await appState.deleteBudgetType(selected.id!);
      if (!mounted || !success) {
        return;
      }
    }
    final refreshedTypes = _availableBudgetTypeKeys(appState);
    if (_selectedType == selected.name && refreshedTypes.isNotEmpty) {
      setState(() => _selectedType = refreshedTypes.first);
    }
  }

  /// Czyści kontrolery pól formularza przy zamykaniu arkusza.
  @override
  void dispose() {
    _nameController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  /// Buduje formularz dodawania budżetu wraz z walidacją i rozwijanymi listami.
  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final appState = context.watch<AppState>();
    final categories =
        appState.categories
            .where((category) => category.type == TransactionType.expense)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final customBudgetTypes = appState.budgetTypes.map((item) => item.name);
    final visibleDefaultTypes = _visibleDefaultBudgetTypes(appState).toList();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(24, 24, 24, viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nowy budżet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nazwa budżetu',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Podaj nazwę budżetu.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Limit budżetu',
                  prefixIcon: Icon(Icons.numbers),
                ),
                validator: (value) {
                  final text = value?.replaceAll(',', '.').trim();
                  if (text == null || text.isEmpty) {
                    return 'Podaj limit.';
                  }
                  final parsed = double.tryParse(text);
                  if (parsed == null || parsed <= 0) {
                    return 'Limit musi być dodatnią liczbą.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Rodzaj budżetu',
                  prefixIcon: Icon(Icons.style_outlined),
                ),
                initialValue: _selectedType,
                items:
                    [
                          ...visibleDefaultTypes,
                          ...customBudgetTypes.map(
                            (type) =>
                                MapEntry(type, _formatBudgetTypeLabel(type)),
                          ),
                        ]
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(
                                  iconForBudgetType(entry.key),
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Text(entry.value),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedType = value);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _canDeleteBudgetTypes(appState)
                        ? _openBudgetTypeDeleter
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Usuń rodzaj'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _openBudgetTypeCreator,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Nowy rodzaj'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Okres budżetu',
                  prefixIcon: Icon(Icons.date_range_outlined),
                ),
                initialValue: _selectedPeriod,
                items: _periods.entries
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedPeriod = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                decoration: const InputDecoration(
                  labelText: 'Powiązana kategoria (opcjonalnie)',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                initialValue: _selectedCategoryId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Brak powiązania'),
                  ),
                  ...categories.map(
                    (category) => DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedCategoryId = value),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Anuluj'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Zapisz'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Waliduje dane, wywołuje `createBudget` i zamyka arkusz, gdy operacja się powiedzie.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final parsedLimit = double.parse(
      _limitController.text.replaceAll(',', '.').trim(),
    );
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _saving = true);
    final success = await appState.createBudget(
      name: _nameController.text.trim(),
      limitAmount: parsedLimit,
      period: _selectedPeriod,
      budgetType: _selectedType,
      categoryId: _selectedCategoryId,
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    if (success) {
      navigator.pop(true);
    } else {
      final message = appState.dataError ?? 'Nie udało się utworzyć budżetu.';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _BudgetTypeDeletionOption {
  const _BudgetTypeDeletionOption({
    required this.name,
    required this.label,
    this.id,
    required this.isDefault,
  });

  final String name;
  final String label;
  final int? id;
  final bool isDefault;
}
