import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  /// Tworzy ekran ustawień profilu, obsługujący edycję danych użytkownika.
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _currencyController = TextEditingController();
  final _incomeController = TextEditingController();
  static const List<String> _currencies = ['PLN', 'EUR', 'USD', 'GBP'];
  String? _selectedCurrency;
  String? _selectedIncomeCurrency;
  int? _incomeDayOfMonth;
  Timer? _saveDebounce;

  UserProfile? _lastSnapshot;
  bool _saving = false;
  bool _exporting = false;
  bool _pendingSave = false;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _displayNameController.dispose();
    super.dispose();
  }

  /// Synchronizuje kontrolki formularza z aktualnym stanem profilu, gdy ten się zmieni.
  void _syncWithUser(UserProfile? user) {
    if (user == null) {
      return;
    }

    final hasChanged =
        _lastSnapshot == null ||
        _lastSnapshot!.email != user.email ||
        _lastSnapshot!.displayName != user.displayName ||
        _lastSnapshot!.defaultCurrency != user.defaultCurrency ||
        _lastSnapshot!.monthlyIncome != user.monthlyIncome ||
        _lastSnapshot!.monthlyIncomeCurrency != user.monthlyIncomeCurrency ||
        _lastSnapshot!.incomeDayOfMonth != user.incomeDayOfMonth;

    if (!hasChanged) {
      return;
    }

    _displayNameController.text = user.displayName ?? '';
    final normalizedCurrency = _normalizeCurrency(user.defaultCurrency);
    _selectedCurrency = normalizedCurrency ?? _currencies.first;
    _currencyController.text = _selectedCurrency ?? _currencies.first;
    final normalizedIncomeCurrency = _normalizeCurrency(
      user.monthlyIncomeCurrency,
    );
    _selectedIncomeCurrency =
        normalizedIncomeCurrency ?? _selectedCurrency ?? _currencies.first;
    final income = user.monthlyIncome;
    _incomeController.text = income.toStringAsFixed(0);
    _incomeDayOfMonth = user.incomeDayOfMonth;

    _lastSnapshot = user;
  }

  String? _normalizeCurrency(String? value) {
    final normalized = value?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return _currencies.contains(normalized) ? normalized : null;
  }

  /// Waliduje i zapisuje zmiany profilu poprzez `AppState`.
  Future<void> _saveProfile(
    AppState appState, {
    bool showSuccess = false,
  }) async {
    if (_saving) {
      _pendingSave = true;
      return;
    }
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final incomeText = _incomeController.text.replaceAll(',', '.');
    final incomeValue = double.tryParse(incomeText) ?? 0;
    final currencyValue = _currencyController.text.trim();
    final incomeCurrencyValue = (_selectedIncomeCurrency ?? _currencies.first)
        .trim();
    final displayNameValue = _displayNameController.text.trim();

    setState(() {
      _saving = true;
    });

    final success = await appState.updateProfileDetails(
      displayName: displayNameValue,
      defaultCurrency: currencyValue,
      monthlyIncome: incomeValue,
      monthlyIncomeCurrency: incomeCurrencyValue,
      incomeDayOfMonth: _incomeDayOfMonth,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });

    if (_pendingSave) {
      _pendingSave = false;
      if (mounted) {
        await _saveProfile(appState);
      }
      return;
    }

    if (success && showSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Zapisano zmiany profilu.')));
    } else if (!success) {
      final message = appState.dataError ?? 'Nie udało się zapisać zmian.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _scheduleAutoSave(AppState appState) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) {
        return;
      }
      _saveProfile(appState);
    });
  }

  /// Wylogowuje użytkownika i pokazuje krótkie potwierdzenie w Snackbarze.
  Future<void> _performLogout(AppState appState) async {
    await appState.logout();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Wylogowano pomyślnie.')));
  }

  /// Wyświetla dolny arkusz z wyborem dnia wypłaty i zapisuje go w stanie.
  Future<void> _selectIncomeDay() async {
    final selectedDay = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final days = List<int>.generate(31, (index) => index + 1);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wybierz dzień wypłaty',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Savoo doda Twój miesięczny dochód w wybranym dniu każdego miesiąca.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.15,
                          ),
                      itemCount: days.length,
                      itemBuilder: (context, index) {
                        final day = days[index];
                        final isSelected = day == _incomeDayOfMonth;
                        final backgroundColor = isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : theme.colorScheme.surface;
                        final borderColor = isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline.withValues(alpha: 0.35);

                        return Semantics(
                          button: true,
                          selected: isSelected,
                          label: 'Dzień $day',
                          child: Material(
                            color: backgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.of(context).pop(day),
                              child: Center(
                                child: Text(
                                  day.toString(),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selectedDay == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _incomeDayOfMonth = selectedDay;
    });
    final appState = context.read<AppState>();
    await _saveProfile(appState);
  }

  Future<void> _exportAllData(AppState appState) async {
    if (_exporting) {
      return;
    }

    setState(() {
      _exporting = true;
    });

    final path = await appState.exportAllDataCsv();

    if (!mounted) {
      return;
    }

    setState(() {
      _exporting = false;
    });

    if (path == null) {
      final message = appState.dataError ?? 'Nie udało się pobrać pliku CSV.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zapisano w katalogu Pobrane.')),
    );
  }

  /// Buduje formularz profilu wraz z akcjami wylogowania i eksportu danych.
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.user;
    final isLoggingOut = appState.logoutInProgress;

    _syncWithUser(user);

    final payDayLabel = _incomeDayOfMonth == null
        ? 'Ustaw dzień wypłaty'
        : 'Wypłata: ${_incomeDayOfMonth!}';
    final payDayDescription = _incomeDayOfMonth == null
        ? 'Wybierz dzień miesiąca, w którym zwykle otrzymujesz przelew z wynagrodzeniem. Savoo wykorzysta tę informację, aby dodać dochód we właściwym czasie.'
        : 'Wybrano ${_incomeDayOfMonth!}. dzień miesiąca jako termin wpływu dochodu. Jeśli miesiąc ma mniej dni, Savoo zaksięguje wypłatę w ostatnim dniu miesiąca.';

    final initials = (user?.displayName?.isNotEmpty ?? false)
        ? user!.displayName!.substring(0, 1).toUpperCase()
        : 'S';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Profil',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName?.isNotEmpty == true
                              ? user!.displayName!
                              : 'Użytkownik Savoo',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(user?.email ?? 'hello@savoo.app'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Wyloguj się',
                    icon: isLoggingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout),
                    onPressed: isLoggingOut
                        ? null
                        : () => _performLogout(appState),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ustawienia profilu',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _displayNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nazwa użytkownika',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onChanged: (_) => _scheduleAutoSave(appState),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      _selectedCurrency ?? _currencies.first,
                    ),
                    initialValue: _selectedCurrency ?? _currencies.first,
                    decoration: const InputDecoration(
                      labelText: 'Domyślna waluta',
                      prefixIcon: Icon(Icons.currency_exchange),
                    ),
                    items: _currencies
                        .map(
                          (currency) => DropdownMenuItem<String>(
                            value: currency,
                            child: Text(currency),
                          ),
                        )
                        .toList(),
                    onChanged: (_saving || isLoggingOut)
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedCurrency = value;
                              _currencyController.text = value;
                            });
                            _saveProfile(appState);
                          },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Wybierz walutę z listy.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _incomeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Miesięczny dochód',
                            prefixIcon: const Icon(Icons.wallet_outlined),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          onChanged: (_) => _scheduleAutoSave(appState),
                          validator: (value) {
                            final sanitized = value?.replaceAll(',', '.') ?? '';
                            final amount = double.tryParse(sanitized);
                            if (amount == null) {
                              return 'Podaj poprawną kwotę.';
                            }
                            if (amount < 0) {
                              return 'Kwota nie może być ujemna.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            _selectedIncomeCurrency ??
                                _selectedCurrency ??
                                _currencies.first,
                          ),
                          initialValue:
                              _selectedIncomeCurrency ??
                              _selectedCurrency ??
                              _currencies.first,
                          decoration: const InputDecoration(
                            labelText: 'Waluta',
                          ),
                          items: _currencies
                              .map(
                                (currency) => DropdownMenuItem<String>(
                                  value: currency,
                                  child: Text(currency),
                                ),
                              )
                              .toList(),
                          onChanged: (_saving || isLoggingOut)
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedIncomeCurrency = value;
                                  });
                                  _saveProfile(appState);
                                },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Wybierz walutę.';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_saving || isLoggingOut)
                          ? null
                          : _selectIncomeDay,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(payDayLabel),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    payDayDescription,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Eksport danych',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pobierz wszystkie swoje dane, które zostaną zapisane w pliku CSV.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: (_exporting || _saving || isLoggingOut)
                        ? null
                        : () => _exportAllData(appState),
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: const Text('Pobierz dane'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
