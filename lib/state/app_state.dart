import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/savoo_api_client.dart';
import '../services/csv_exporter.dart';

/// Reprezentuje podstawowe dane profilu, które pobieramy z backendu.
class UserProfile {
  /// Tworzy obiekt profilu z danymi podstawowymi użytkownika.
  /// Pola opcjonalne pozwalają przechowywać nazwę i ustawienia finansowe.
  UserProfile({
    required this.email,
    this.displayName,
    this.defaultCurrency = 'PLN',
    this.monthlyIncome = 0,
    this.monthlyIncomeCurrency = 'PLN',
    this.incomeDayOfMonth,
  });

  final String email;
  final String? displayName;
  final String defaultCurrency;
  final double monthlyIncome;
  final String monthlyIncomeCurrency;
  final int? incomeDayOfMonth;
}

/// Zawiera zagregowane dane finansowe wyświetlane na pulpicie.
class SummaryData {
  /// Buduje podsumowanie dla wskazanego okresu i zsumowanych wartości.
  /// Zawiera także listę najwyższych wydatków kategorii.
  SummaryData({
    required this.periodStart,
    required this.periodEnd,
    required this.totalIncome,
    required this.totalExpense,
    required this.netSavings,
    required this.topExpenseCategories,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final double totalIncome;
  final double totalExpense;
  final double netSavings;
  final List<CategorySummary> topExpenseCategories;
}

/// Podsumowanie wydatków w danej kategorii do widgetu pulpitu.
class CategorySummary {
  /// Tworzy element podsumowania kategorii z nazwą i kwotą wydatków.
  CategorySummary({required this.name, required this.spent});

  final String name;
  final double spent;
}

/// Wyróżnia główne typy transakcji obsługiwane w aplikacji.
enum TransactionType { income, expense, transfer }

/// Dodatkowa kategoryzacja transakcji, wykorzystywana w UI.
enum TransactionKind {
  general,
  household,
  entertainment,
  savings,
  travel,
  education,
  health,
  investment,
  salary,
  bonus,
  gift,
  other,
}

/// Model pojedynczej transakcji wraz z metadanymi.
class TransactionItem {
  /// Tworzy transakcję wraz z typem, kategorią i metadanymi.
  /// Opcjonalne pola opisują powiązania z kategorią i budżetem.
  TransactionItem({
    required this.title,
    required this.category,
    required this.amount,
    required this.type,
    required this.kind,
    required this.occurredOn,
    required this.currency,
    this.displayAmount,
    this.displayCurrency,
    this.note,
    this.id,
    this.categoryId,
    this.budgetId,
    this.budgetName,
    this.isAutoIncome = false,
  });

  final String title;
  final String category;
  final double amount;
  final TransactionType type;
  final TransactionKind kind;
  final DateTime occurredOn;
  final String currency;
  final double? displayAmount;
  final String? displayCurrency;
  final String? note;
  final int? id;
  final int? categoryId;
  final int? budgetId;
  final String? budgetName;
  final bool isAutoIncome;
}

/// Opisuje kategorię wydatków/przychodów możliwą do wyboru w formach.
class CategoryItem {
  /// Tworzy kategorię z identyfikatorem, nazwą i typem transakcji.
  /// Opcjonalnie zawiera kolor oraz ikonę do UI.
  CategoryItem({
    required this.id,
    required this.name,
    required this.type,
    this.color,
    this.iconUrl,
  });

  final int id;
  final String name;
  final TransactionType type;
  final String? color;
  final String? iconUrl;
}

/// Opisuje własny rodzaj budżetu zapisany przez użytkownika.
class BudgetTypeItem {
  /// Tworzy prosty model rodzaju budżetu z identyfikatorem i nazwą.
  BudgetTypeItem({required this.id, required this.name});

  final int id;
  final String name;
}

/// Model limitu budżetowego wraz z wykorzystaniem i datami.
class BudgetItem {
  /// Tworzy budżet z limitem, wydatkami oraz okresem rozliczeń.
  /// Pola opcjonalne pozwalają na powiązania i zakres dat.
  BudgetItem({
    required this.id,
    required this.name,
    required this.limitAmount,
    required this.spentAmount,
    required this.period,
    required this.budgetType,
    required this.currency,
    this.category,
    this.startDate,
    this.endDate,
    this.remainingAmount,
    this.transactionCount = 0,
  });

  final int id;
  final String name;
  final double limitAmount;
  final double spentAmount;
  final String period;
  final String budgetType;
  final String currency;
  final String? category;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? remainingAmount;
  final int transactionCount;

  /// Udział wydanej kwoty w limicie budżetowym.
  /// Zwraca wartość z zakresu 0–1 dla prostego użycia w UI.
  double get progress => limitAmount <= 0
      ? 0
      : (spentAmount / limitAmount).clamp(0.0, 1.0).toDouble();

  /// Kwota, która pozostała do wykorzystania w tym budżecie.
  /// Jeśli backend nie podał wartości, wylicza ją lokalnie.
  double get remaining => remainingAmount ?? (limitAmount - spentAmount);
}

/// Reprezentuje cel oszczędnościowy wraz z postępem i terminem.
class SavingsGoalItem {
  /// Buduje cel oszczędnościowy wraz z kwotami i statusem aktywności.
  /// Opcjonalne pola opisują termin oraz daty utworzenia i modyfikacji.
  SavingsGoalItem({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.contributedAmount,
    required this.remainingAmount,
    required this.isActive,
    this.progressPercent,
    this.deadline,
    this.categoryId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final double contributedAmount;
  final double remainingAmount;
  final bool isActive;
  final double? progressPercent;
  final DateTime? deadline;
  final int? categoryId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Procent realizacji celu w odniesieniu do kwoty docelowej.
  /// Zwraca wartość z zakresu 0–1 wygodną do wizualizacji.
  double get progress => targetAmount <= 0
      ? 0
      : (currentAmount / targetAmount).clamp(0.0, 1.0).toDouble();
}

/// Centralny stan aplikacji odpowiedzialny za logowanie i synchronizację danych.
class AppState extends ChangeNotifier {
  /// Tworzy stan aplikacji i wiąże go z klientem API.
  /// Klient dostarcza operacje sieciowe i przechowuje sesję.
  AppState(this._apiClient);

  final SavooApiClient _apiClient;
  static const String _hiddenDefaultBudgetTypesKey =
      'hidden_default_budget_types';

  UserProfile? user;
  SummaryData? summary;
  List<TransactionItem> transactions = [];
  List<BudgetItem> budgets = [];
  List<CategoryItem> categories = [];
  List<BudgetTypeItem> budgetTypes = [];
  List<SavingsGoalItem> savingsGoals = [];
  final Set<String> hiddenDefaultBudgetTypes = {};

  bool isLoading = false;
  bool isBootstrapping = true;
  bool isAuthenticated = false;
  bool authInProgress = false;
  bool logoutInProgress = false;
  String? authError;
  String? dataError;

  /// Czyści lokalny stan i przygotowuje aplikację do działania przed logowaniem.
  /// Resetuje sesję API i odświeża stan pamiętany lokalnie.
  Future<void> bootstrap() async {
    _apiClient.clearSession();
    user = null;
    summary = null;
    budgets = [];
    transactions = [];
    categories = [];
    budgetTypes = [];
    savingsGoals = [];
    await _loadHiddenDefaultBudgetTypes();
    isAuthenticated = false;
    authError = null;
    dataError = null;
    isBootstrapping = false;
    notifyListeners();
  }

  /// Loguje użytkownika i po udanym uwierzytelnieniu odświeża dashboard.
  /// Zwraca informację o powodzeniu, aby UI mógł reagować.
  Future<bool> login(String email, String password) async {
    authError = null;
    authInProgress = true;
    notifyListeners();
    try {
      final payload = await _apiClient.login(email: email, password: password);
      _applyAuthPayload(payload, email: email, password: password);
      unawaited(refreshDashboard());
      return true;
    } on SavooApiException catch (error) {
      authError = error.message;
      return false;
    } catch (_) {
      authError = 'Nie udało się zalogować. Spróbuj ponownie.';
      return false;
    } finally {
      authInProgress = false;
      notifyListeners();
    }
  }

  /// Tworzy nowe konto w backendzie, a następnie loguje użytkownika.
  /// W razie błędu zapisuje komunikat do wyświetlenia w UI.
  Future<bool> register(
    String email,
    String password,
    String displayName, {
    required String securityQuestionKey,
    required String securityAnswer,
  }) async {
    authError = null;
    authInProgress = true;
    notifyListeners();
    try {
      final payload = await _apiClient.register(
        email: email,
        password: password,
        displayName: displayName,
        securityQuestionKey: securityQuestionKey,
        securityAnswer: securityAnswer,
      );
      _applyAuthPayload(payload, email: email, password: password);
      await refreshDashboard();
      return true;
    } on SavooApiException catch (error) {
      authError = error.message;
      return false;
    } catch (_) {
      authError = 'Nie udało się utworzyć konta. Spróbuj ponownie.';
      return false;
    } finally {
      authInProgress = false;
      notifyListeners();
    }
  }

  /// Inicjuje proces resetu hasła poprzez weryfikację pytania bezpieczeństwa.
  /// Zwraca token wymagany w drugim kroku resetu.
  Future<String> requestPasswordResetToken({
    required String email,
    required String securityQuestionKey,
    required String securityAnswer,
  }) {
    return _apiClient.startPasswordReset(
      email: email,
      securityQuestionKey: securityQuestionKey,
      securityAnswer: securityAnswer,
    );
  }

  /// Finalizuje reset hasła wykorzystując token otrzymany po weryfikacji pytania.
  /// Backend weryfikuje zgodność danych i zapisuje nowe hasło.
  Future<void> resetPasswordWithToken({
    required String email,
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _apiClient.completePasswordReset(
      email: email,
      resetToken: resetToken,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  /// Wylogowuje użytkownika lokalnie i w backendzie, zerując wszystkie dane.
  /// Zawsze czyści stan lokalny nawet przy błędzie sieci.
  Future<void> logout() async {
    if (logoutInProgress) {
      return;
    }
    logoutInProgress = true;
    notifyListeners();
    try {
      await _apiClient.logout();
    } catch (_) {}
    _apiClient.clearSession();
    user = null;
    summary = null;
    transactions = [];
    budgets = [];
    categories = [];
    budgetTypes = [];
    savingsGoals = [];
    isAuthenticated = false;
    authError = null;
    dataError = null;
    logoutInProgress = false;
    notifyListeners();
  }

  /// Ukrywa domyślny rodzaj budżetu dostępny lokalnie w aplikacji.
  /// Zapisuje decyzję w pamięci lokalnej użytkownika.
  void hideDefaultBudgetType(String type) {
    if (hiddenDefaultBudgetTypes.add(type)) {
      _persistHiddenDefaultBudgetTypes();
      notifyListeners();
    }
  }

  /// Odczytuje ukryte domyślne typy budżetu z pamięci lokalnej.
  /// Zapobiega ich ponownemu pokazywaniu w UI po restarcie.
  Future<void> _loadHiddenDefaultBudgetTypes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_hiddenDefaultBudgetTypesKey) ?? [];
      hiddenDefaultBudgetTypes
        ..clear()
        ..addAll(stored);
    } catch (_) {
      hiddenDefaultBudgetTypes.clear();
    }
  }

  /// Zapisuje listę ukrytych domyślnych typów budżetu lokalnie.
  /// Błędy zapisu są ignorowane, aby nie blokować UI.
  Future<void> _persistHiddenDefaultBudgetTypes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _hiddenDefaultBudgetTypesKey,
        hiddenDefaultBudgetTypes.toList()..sort(),
      );
    } catch (_) {}
  }

  /// Aktualizuje dane profilu i normalizuje pola wejściowe.
  /// Waliduje dzień wypłaty oraz walutę przed wysłaniem.
  Future<bool> updateProfileDetails({
    String? displayName,
    double? monthlyIncome,
    String? monthlyIncomeCurrency,
    String? defaultCurrency,
    int? incomeDayOfMonth,
  }) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    final rawDisplayName = (displayName ?? currentUser.displayName ?? '')
        .trim();
    final effectiveDisplayName = rawDisplayName.isEmpty
        ? (currentUser.displayName ?? '')
        : rawDisplayName;
    final rawCurrency = (defaultCurrency ?? currentUser.defaultCurrency)
        .trim()
        .toUpperCase();
    final effectiveCurrency = rawCurrency.isEmpty
        ? currentUser.defaultCurrency
        : rawCurrency;
    final rawIncomeCurrency =
        (monthlyIncomeCurrency ?? currentUser.monthlyIncomeCurrency)
            .trim()
            .toUpperCase();
    final effectiveIncomeCurrency = rawIncomeCurrency.isEmpty
        ? currentUser.monthlyIncomeCurrency
        : rawIncomeCurrency;
    final effectiveIncome = monthlyIncome ?? currentUser.monthlyIncome;
    final rawIncomeDay = incomeDayOfMonth ?? currentUser.incomeDayOfMonth;
    int? effectiveIncomeDay;
    if (rawIncomeDay != null) {
      if (rawIncomeDay < 1) {
        effectiveIncomeDay = 1;
      } else if (rawIncomeDay > 31) {
        effectiveIncomeDay = 31;
      } else {
        effectiveIncomeDay = rawIncomeDay;
      }
    }

    try {
      await _apiClient.updateProfile(
        displayName: effectiveDisplayName,
        defaultCurrency: effectiveCurrency,
        monthlyIncome: effectiveIncome,
        monthlyIncomeCurrency: effectiveIncomeCurrency,
        monthlyIncomeDay: effectiveIncomeDay,
      );

      user = UserProfile(
        email: currentUser.email,
        displayName: effectiveDisplayName.isEmpty
            ? currentUser.displayName
            : effectiveDisplayName,
        defaultCurrency: effectiveCurrency,
        monthlyIncome: effectiveIncome,
        monthlyIncomeCurrency: effectiveIncomeCurrency,
        incomeDayOfMonth: effectiveIncomeDay,
      );
      notifyListeners();

      unawaited(refreshDashboard());
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      dataError = 'Nie udało się zaktualizować profilu. Spróbuj ponownie.';
      notifyListeners();
      return false;
    }
  }

  /// Eksportuje wszystkie dane użytkownika do pliku CSV.
  /// Zwraca ścieżkę do zapisanego pliku lub `null`, gdy eksport się nie uda.
  Future<String?> exportAllDataCsv() async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return null;
    }

    try {
      final bytes = await _apiClient.exportAllDataCsv();
      final rawLabel = (currentUser.displayName?.trim().isNotEmpty ?? false)
          ? currentUser.displayName!.trim()
          : currentUser.email;
      final safeLabel = rawLabel.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final dateLabel = DateTime.now().toIso8601String().split('T').first;
      final fileName = 'savoo_export_${safeLabel}_$dateLabel.csv';
      final path = await CsvExporter.saveCsv(
        Uint8List.fromList(bytes),
        fileName: fileName,
      );
      return path;
    } on SavooApiException catch (error) {
      dataError = error.message;
      notifyListeners();
      return null;
    } on UnsupportedError catch (error) {
      dataError = error.message;
      notifyListeners();
      return null;
    } catch (_) {
      dataError = 'Nie udało się wyeksportować danych.';
      notifyListeners();
      return null;
    }
  }

  /// Pobiera wszystkie główne sekcje danych i reaguje na błędy autoryzacji.
  /// Przy nieudanym podsumowaniu tworzy lokalny fallback.
  Future<void> refreshDashboard() async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      summary = null;
      transactions = [];
      categories = [];
      budgetTypes = [];
      savingsGoals = [];
      notifyListeners();
      return;
    }
    isLoading = true;
    dataError = null;
    notifyListeners();

    SavooApiException? capturedError;
    var transactionsLoaded = false;
    var summaryLoaded = false;

    try {
      await _loadCategories();
    } on SavooApiException catch (error) {
      capturedError ??= error;
    }

    try {
      await _loadBudgetTypes();
    } on SavooApiException catch (error) {
      capturedError ??= error;
    }

    try {
      await _loadTransactions();
      transactionsLoaded = true;
      await _ensureAutomaticIncomeCredit();
    } on SavooApiException catch (error) {
      capturedError ??= error;
    }

    try {
      await _loadBudgets();
    } on SavooApiException catch (error) {
      capturedError ??= error;
    }

    try {
      await _loadSavingsGoals();
    } on SavooApiException catch (error) {
      capturedError ??= error;
    }

    try {
      await _loadSummary(currentUser);
      summaryLoaded = true;
    } on SavooApiException catch (error) {
      capturedError ??= error;
    }

    if (!summaryLoaded && transactionsLoaded) {
      summary = _buildLocalSummary();
    }

    if (capturedError != null) {
      dataError = capturedError.message;
      if (capturedError.statusCode == 401) {
        isLoading = false;
        await logout();
        return;
      }
    }

    isLoading = false;
    notifyListeners();
  }

  /// Konwertuje odpowiedź API pulpitu na obiekt `SummaryData`.
  /// Zapewnia wartości domyślne w razie braków w JSON.
  SummaryData _mapSummary(Map<String, dynamic> summaryJson) {
    final categories =
        (summaryJson['top_expense_categories'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(
              (item) => CategorySummary(
                name: (item['name'] ?? '-') as String,
                spent: (item['spent'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList();

    return SummaryData(
      periodStart:
          DateTime.tryParse(summaryJson['period_start'] as String? ?? '') ??
          DateTime(DateTime.now().year, DateTime.now().month, 1),
      periodEnd:
          DateTime.tryParse(summaryJson['period_end'] as String? ?? '') ??
          DateTime(
            DateTime.now().year,
            DateTime.now().month + 1,
            0,
            23,
            59,
            59,
            999,
          ),
      totalIncome: (summaryJson['total_income'] as num?)?.toDouble() ?? 0,
      totalExpense: (summaryJson['total_expense'] as num?)?.toDouble() ?? 0,
      netSavings: (summaryJson['net_savings'] as num?)?.toDouble() ?? 0,
      topExpenseCategories: categories,
    );
  }

  /// Tworzy lokalne podsumowanie z już pobranych transakcji.
  /// Stosowane jako fallback, gdy backend nie zwróci danych.
  SummaryData _buildLocalSummary() {
    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month, 1);
    final periodEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);

    final monthTransactions = transactions.where(
      (txn) =>
          !txn.occurredOn.isBefore(periodStart) &&
          !txn.occurredOn.isAfter(periodEnd),
    );

    final totalIncome = monthTransactions
        .where((txn) => txn.type == TransactionType.income)
        .fold<double>(0, (sum, txn) => sum + txn.amount);
    final totalExpense = monthTransactions
        .where((txn) => txn.type == TransactionType.expense)
        .fold<double>(0, (sum, txn) => sum + txn.amount);
    final Map<String, double> expenseByCategory = {};
    for (final txn in monthTransactions.where(
      (txn) => txn.type == TransactionType.expense,
    )) {
      expenseByCategory.update(
        txn.category,
        (value) => value + txn.amount,
        ifAbsent: () => txn.amount,
      );
    }
    final topCategories =
        expenseByCategory.entries
            .map(
              (entry) => CategorySummary(name: entry.key, spent: entry.value),
            )
            .toList()
          ..sort((a, b) => b.spent.compareTo(a.spent));

    return SummaryData(
      periodStart: periodStart,
      periodEnd: periodEnd,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      netSavings: totalIncome - totalExpense,
      topExpenseCategories: topCategories.take(5).toList(),
    );
  }

  /// Ściąga kategorie z API i publikuje je w stanie.
  /// Aktualizuje listę używaną w formularzach.
  Future<void> _loadCategories() async {
    final rawCategories = await _apiClient.fetchCategories();
    categories = rawCategories.map(_mapCategory).toList();
    notifyListeners();
  }

  /// Ściąga własne typy budżetów z API i publikuje je w stanie.
  /// Pozwala UI wyświetlić nowe typy użytkownika.
  Future<void> _loadBudgetTypes() async {
    final rawTypes = await _apiClient.fetchBudgetTypes();
    budgetTypes = rawTypes.map(_mapBudgetType).toList();
    notifyListeners();
  }

  /// Ładuje transakcje z backendu i powiadamia obserwatorów.
  /// Po mapowaniu odświeża listę w UI.
  Future<void> _loadTransactions() async {
    final rawTransactions = await _apiClient.fetchTransactions();
    transactions = rawTransactions.map(_mapTransaction).toList();
    notifyListeners();
  }

  /// Odświeża listę celów oszczędnościowych.
  /// Po pobraniu mapuje JSON do modeli aplikacji.
  Future<void> _loadSavingsGoals() async {
    final rawGoals = await _apiClient.fetchSavingsGoals();
    savingsGoals = rawGoals.map(_mapSavingsGoal).toList();
    notifyListeners();
  }

  /// Dokłada automatyczny wpływ pensji, jeśli termin wypłaty już minął.
  /// Zapobiega duplikatom w tym samym miesiącu.
  Future<void> _ensureAutomaticIncomeCredit() async {
    final profile = user;
    if (!isAuthenticated || profile == null) {
      return;
    }

    final incomeDay = profile.incomeDayOfMonth;
    final monthlyIncome = profile.monthlyIncome;
    if (incomeDay == null || incomeDay < 1 || monthlyIncome <= 0) {
      return;
    }

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final scheduledDay = incomeDay > daysInMonth ? daysInMonth : incomeDay;
    final scheduledDate = DateTime(now.year, now.month, scheduledDay);

    if (now.isBefore(scheduledDate)) {
      return;
    }

    final hasAutoIncome = transactions.any(
      (txn) =>
          txn.type == TransactionType.income &&
          txn.isAutoIncome &&
          txn.occurredOn.year == now.year &&
          txn.occurredOn.month == now.month,
    );

    if (hasAutoIncome) {
      return;
    }

    final notePayload = jsonEncode({
      'title': 'Automatyczna wypłata',
      'note': 'Automatyczny wpływ miesięcznego dochodu.',
      'auto_income': true,
    });

    try {
      await _apiClient.createTransaction(
        amount: monthlyIncome,
        type: 'income',
        occurredOn: scheduledDate,
        currency: profile.monthlyIncomeCurrency,
        kind: _transactionKindToApi(TransactionKind.salary),
        note: notePayload,
      );
    } on SavooApiException catch (error) {
      dataError ??= error.message;
      if (error.statusCode == 401) {
        await logout();
      }
      return;
    } catch (_) {
      dataError ??= 'Nie udało się zaksięgować automatycznej wypłaty.';
      return;
    }

    await _loadTransactions();
  }

  /// Pobiera aktualne budżety użytkownika.
  /// Zapisuje je w stanie do wyświetlenia w UI.
  Future<void> _loadBudgets() async {
    final rawBudgets = await _apiClient.fetchBudgets();
    budgets = rawBudgets.map(_mapBudget).toList();
    notifyListeners();
  }

  /// Ładuje podsumowanie z backendu dla bieżącego użytkownika.
  /// Ustawia `summary` lub czyści je przy braku danych.
  Future<void> _loadSummary(UserProfile currentUser) async {
    final summaryJson = await _apiClient.fetchSummary(currentUser.email);
    if (summaryJson != null) {
      summary = _mapSummary(summaryJson);
    } else {
      summary = null;
    }
  }

  /// Zamienia surowy JSON kategorii na `CategoryItem`.
  /// Utrzymuje bezpieczne wartości domyślne.
  CategoryItem _mapCategory(Map<String, dynamic> json) {
    final typeValue = (json['type'] as String?)?.toLowerCase() ?? 'expense';
    return CategoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim() ?? 'Kategoria',
      type: _parseTransactionType(typeValue),
      color: json['color'] as String?,
      iconUrl: json['icon_url'] as String?,
    );
  }

  /// Zamienia surowy JSON typu budżetu na `BudgetTypeItem`.
  /// Dba o bezpieczne wartości domyślne.
  BudgetTypeItem _mapBudgetType(Map<String, dynamic> json) {
    return BudgetTypeItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim() ?? '',
    );
  }

  /// Konwertuje wpis celu oszczędnościowego do modelu aplikacji.
  /// Normalizuje daty i wartości kwotowe.
  SavingsGoalItem _mapSavingsGoal(Map<String, dynamic> json) {
    final deadlineRaw = json['deadline'] as String?;
    final createdRaw = json['created_at'] as String?;
    final updatedRaw = json['updated_at'] as String?;
    final targetAmount = (json['target_amount'] as num?)?.toDouble() ?? 0;
    final currentAmount = (json['current_amount'] as num?)?.toDouble() ?? 0;
    final contributed =
        (json['contributed_amount'] as num?)?.toDouble() ?? currentAmount;
    final remaining =
        (json['remaining_amount'] as num?)?.toDouble() ??
        (targetAmount - currentAmount);

    return SavingsGoalItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim() ?? 'Cel oszczędnościowy',
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      contributedAmount: contributed,
      remainingAmount: remaining < 0 ? 0 : remaining,
      isActive: (json['is_active'] as int?) != 0,
      progressPercent: (json['progress_percent'] as num?)?.toDouble(),
      deadline: deadlineRaw == null ? null : DateTime.tryParse(deadlineRaw),
      categoryId: (json['category_id'] as num?)?.toInt(),
      createdAt: createdRaw == null ? null : DateTime.tryParse(createdRaw),
      updatedAt: updatedRaw == null ? null : DateTime.tryParse(updatedRaw),
    );
  }

  /// Tworzy obiekt budżetu na podstawie odpowiedzi API.
  /// Uzupełnia nazwy kategorii i okresy rozliczeń.
  BudgetItem _mapBudget(Map<String, dynamic> json) {
    final categoryId = (json['category_id'] as num?)?.toInt();
    final startDateRaw = json['start_date'] as String?;
    final endDateRaw = json['end_date'] as String?;
    return BudgetItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim() ?? 'Budżet',
      limitAmount: (json['limit_amount'] as num?)?.toDouble() ?? 0,
      spentAmount: (json['spent_amount'] as num?)?.toDouble() ?? 0,
      period: (json['period'] as String?) ?? 'monthly',
      budgetType: (json['budget_type'] as String?) ?? 'custom',
      currency: (json['currency'] as String?) ?? user?.defaultCurrency ?? 'PLN',
      category: _resolveCategoryName(categoryId, TransactionType.expense),
      startDate: startDateRaw == null ? null : DateTime.tryParse(startDateRaw),
      endDate: endDateRaw == null ? null : DateTime.tryParse(endDateRaw),
      remainingAmount: (json['remaining'] as num?)?.toDouble(),
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Buduje `TransactionItem` i ustala etykiety na podstawie kategorii/budżetu.
  /// Odczytuje też dane z pola notatki dla lepszego opisu.
  TransactionItem _mapTransaction(Map<String, dynamic> json) {
    final typeString = (json['type'] as String?)?.toLowerCase() ?? 'expense';
    final type = _parseTransactionType(typeString);
    final categoryId = (json['category_id'] as num?)?.toInt();
    final categoryName = _resolveCategoryName(categoryId, type);
    final noteDetails = _decodeNotePayload(json['note'] as String?);
    final occurredOnRaw = json['occurred_on'] as String?;
    final kindString = (json['kind'] as String?)?.toLowerCase() ?? 'general';
    final kind = _parseTransactionKind(kindString);
    final budgetId = (json['budget_id'] as num?)?.toInt();
    final budgetName = _resolveBudgetName(
      budgetId,
      (json['budget_name'] as String?)?.trim(),
    );

    return TransactionItem(
      id: (json['id'] as num?)?.toInt(),
      categoryId: categoryId,
      title:
          noteDetails.title ??
          categoryName ??
          budgetName ??
          _labelForType(type),
      category: categoryName ?? budgetName ?? _labelForType(type),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: type,
      kind: kind,
      occurredOn: DateTime.tryParse(occurredOnRaw ?? '') ?? DateTime.now(),
      currency: (json['currency'] as String?) ?? user?.defaultCurrency ?? 'PLN',
      displayAmount: (json['display_amount'] as num?)?.toDouble(),
      displayCurrency:
          (json['display_currency'] as String?) ?? user?.defaultCurrency,
      note: noteDetails.note,
      budgetId: budgetId,
      budgetName: budgetName,
      isAutoIncome: noteDetails.isAutoIncome,
    );
  }

  /// Tłumaczy string z API na enum `TransactionType`.
  /// Zapewnia bezpieczny fallback dla nieznanych wartości.
  TransactionType _parseTransactionType(String value) {
    switch (value.toLowerCase()) {
      case 'income':
        return TransactionType.income;
      case 'transfer':
        return TransactionType.transfer;
      case 'expense':
      default:
        return TransactionType.expense;
    }
  }

  /// Zamienia tekstowy opis rodzaju transakcji na enum aplikacji.
  /// Obsługuje polskie i angielskie etykiety.
  TransactionKind _parseTransactionKind(String value) {
    switch (value.toLowerCase()) {
      case 'general':
      case 'ogolny':
      case 'ogolna':
      case 'ogolne':
        return TransactionKind.general;
      case 'household':
      case 'domowy':
        return TransactionKind.household;
      case 'entertainment':
      case 'rozrywka':
        return TransactionKind.entertainment;
      case 'savings':
      case 'oszczednosci':
        return TransactionKind.savings;
      case 'travel':
      case 'podroze':
        return TransactionKind.travel;
      case 'education':
      case 'edukacja':
        return TransactionKind.education;
      case 'health':
      case 'zdrowie':
        return TransactionKind.health;
      case 'investment':
      case 'inwestycja':
        return TransactionKind.investment;
      case 'salary':
      case 'pensja':
        return TransactionKind.salary;
      case 'bonus':
        return TransactionKind.bonus;
      case 'gift':
      case 'prezent':
        return TransactionKind.gift;
      case 'other':
      default:
        return TransactionKind.other;
    }
  }

  /// Mapuje enum rodzaju transakcji na wartość oczekiwaną przez backend.
  /// Ujednolica format wysyłany w żądaniach API.
  String _transactionKindToApi(TransactionKind kind) {
    switch (kind) {
      case TransactionKind.household:
        return 'household';
      case TransactionKind.entertainment:
        return 'entertainment';
      case TransactionKind.savings:
        return 'savings';
      case TransactionKind.travel:
        return 'travel';
      case TransactionKind.education:
        return 'education';
      case TransactionKind.health:
        return 'health';
      case TransactionKind.investment:
        return 'investment';
      case TransactionKind.salary:
        return 'salary';
      case TransactionKind.bonus:
        return 'bonus';
      case TransactionKind.gift:
        return 'gift';
      case TransactionKind.other:
        return 'other';
      case TransactionKind.general:
        return 'general';
    }
  }

  /// Zwraca przyjazną etykietę (PL) dla UI na podstawie rodzaju transakcji.
  /// Używane w listach i formularzach.
  String transactionKindLabel(TransactionKind kind) {
    switch (kind) {
      case TransactionKind.household:
        return 'Domowy';
      case TransactionKind.entertainment:
        return 'Rozrywka';
      case TransactionKind.savings:
        return 'Oszczędności';
      case TransactionKind.travel:
        return 'Podróże';
      case TransactionKind.education:
        return 'Edukacja';
      case TransactionKind.health:
        return 'Zdrowie';
      case TransactionKind.investment:
        return 'Inwestycja';
      case TransactionKind.salary:
        return 'Pensja';
      case TransactionKind.bonus:
        return 'Premia';
      case TransactionKind.gift:
        return 'Prezent';
      case TransactionKind.other:
        return 'Inne';
      case TransactionKind.general:
        return 'Ogólna';
    }
  }

  /// Konwertuje typ transakcji na string, który akceptuje API.
  /// Utrzymuje spójność danych wysyłanych do backendu.
  String _transactionTypeToApi(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'income';
      case TransactionType.transfer:
        return 'transfer';
      case TransactionType.expense:
        return 'expense';
    }
  }

  /// Zwraca domyślną nazwę tytułu transakcji zależnie od typu.
  /// Stosowane, gdy brak własnego tytułu lub kategorii.
  String _labelForType(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Przychód';
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.expense:
        return 'Wydatek';
    }
  }

  /// Odszukuje nazwę kategorii po ID; fallbackuje do ogólnej etykiety.
  /// Zwraca `null` gdy nie ma kategorii i brak sensownego fallbacku.
  String? _resolveCategoryName(int? categoryId, TransactionType type) {
    if (categoryId == null) {
      return null;
    }
    for (final category in categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }
    return type == TransactionType.expense ? 'Wydatek' : null;
  }

  /// Zwraca nazwę budżetu po ID lub używa tekstu z backendu.
  /// Dzięki temu lista transakcji jest czytelna.
  String? _resolveBudgetName(int? budgetId, String? fallback) {
    final trimmed = fallback?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if (budgetId == null) {
      return null;
    }
    for (final budget in budgets) {
      if (budget.id == budgetId) {
        return budget.name;
      }
    }
    return null;
  }

  /// Pomaga odnaleźć ID kategorii po nazwie w momencie zapisu transakcji.
  /// Używane, gdy formularz zwraca jedynie etykietę.
  int? _findCategoryIdByName(String name, TransactionType type) {
    final normalized = name.trim().toLowerCase();
    for (final category in categories) {
      if (category.type == type &&
          category.name.trim().toLowerCase() == normalized) {
        return category.id;
      }
    }
    return null;
  }

  /// Parsuje notatkę JSON zapisaną w bazie i wyciąga pomocnicze informacje.
  /// Wspiera tytuł, notatkę i flagę auto-przychodu.
  _NoteDetails _decodeNotePayload(String? rawNote) {
    if (rawNote == null || rawNote.trim().isEmpty) {
      return const _NoteDetails();
    }

    final trimmed = rawNote.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final title = (decoded['title'] as String?)?.trim();
        final note = (decoded['note'] as String?)?.trim();
        final autoIncome = decoded['auto_income'] == true;
        return _NoteDetails(
          title: (title == null || title.isEmpty) ? null : title,
          note: (note == null || note.isEmpty) ? null : note,
          isAutoIncome: autoIncome,
        );
      }
    } catch (_) {}

    return _NoteDetails(title: trimmed);
  }

  /// Koduje tytuł/notatkę/flagę auto-income do JSON przechowywanego w polu note.
  /// Zwraca `null`, gdy nie ma nic do zapisania.
  String? _encodeNotePayload(TransactionItem transaction) {
    final title = transaction.title.trim();
    final note = transaction.note?.trim() ?? '';
    final hasTitle = title.isNotEmpty;
    final hasNote = note.isNotEmpty;
    final includeAutoFlag = transaction.isAutoIncome;
    if (!hasTitle && !hasNote && !includeAutoFlag) {
      return null;
    }
    final payload = <String, dynamic>{};
    if (hasTitle) {
      payload['title'] = title;
    }
    if (hasNote) {
      payload['note'] = note;
    }
    if (includeAutoFlag) {
      payload['auto_income'] = true;
    }
    return jsonEncode(payload);
  }

  /// Ustawia sesję HTTP i stan użytkownika na podstawie danych logowania.
  /// Oczyszcza dane lokalne i przygotowuje aplikację do pobrania sekcji.
  void _applyAuthPayload(
    Map<String, dynamic> payload, {
    required String email,
    required String password,
  }) {
    final userJson = payload['user'] as Map<String, dynamic>?;
    if (userJson == null) {
      throw SavooApiException('Nieprawidłowa odpowiedź serwera.');
    }

    final payloadEmail = (userJson['email'] as String?)?.trim();
    final resolvedEmail = (payloadEmail == null || payloadEmail.isEmpty)
        ? email.trim()
        : payloadEmail;
    if (resolvedEmail.isEmpty) {
      throw SavooApiException('Brak adresu e-mail w odpowiedzi serwera.');
    }

    _apiClient.updateSession(email: resolvedEmail, password: password);

    user = UserProfile(
      email: resolvedEmail,
      displayName: userJson['display_name'] as String?,
      defaultCurrency: (userJson['default_currency'] as String?) ?? 'PLN',
      monthlyIncome: (userJson['monthly_income'] as num?)?.toDouble() ?? 0,
      monthlyIncomeCurrency:
          (userJson['monthly_income_currency'] as String?) ??
          (userJson['default_currency'] as String?) ??
          'PLN',
      incomeDayOfMonth: (userJson['monthly_income_day'] as num?)?.toInt(),
    );

    isAuthenticated = true;
    summary = null;
    transactions = [];
    budgets = [];
    categories = [];
    dataError = null;
  }

  /// Generuje przykładowy wydatek, wykorzystywany np. przy demo interfejsu.
  /// Dobiera kategorię z listy lub używa wartości zapasowej.
  TransactionItem buildRandomExpense() {
    final expenseCategories = categories
        .where((item) => item.type == TransactionType.expense)
        .toList();
    if (expenseCategories.isNotEmpty) {
      final selected =
          expenseCategories[Random().nextInt(expenseCategories.length)];
      return TransactionItem(
        title: selected.name,
        category: selected.name,
        amount: 50 + Random().nextDouble() * 250,
        type: TransactionType.expense,
        kind: TransactionKind.general,
        occurredOn: DateTime.now(),
        currency: user?.defaultCurrency ?? 'PLN',
        categoryId: selected.id,
      );
    }
    const fallback = ['Żywność', 'Transport', 'Rozrywka', 'Zdrowie'];
    final category = fallback[Random().nextInt(fallback.length)];
    return TransactionItem(
      title: category,
      category: category,
      amount: 50 + Random().nextDouble() * 250,
      type: TransactionType.expense,
      kind: TransactionKind.general,
      occurredOn: DateTime.now(),
      currency: user?.defaultCurrency ?? 'PLN',
    );
  }

  /// Dodaje transakcję przez API oraz odświeża powiązane sekcje stanu.
  /// Po sukcesie odświeża listy i podsumowanie.
  Future<bool> addTransaction(TransactionItem transaction) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    isLoading = true;
    dataError = null;
    notifyListeners();

    final categoryId = transaction.type == TransactionType.expense
        ? (transaction.categoryId ??
              _findCategoryIdByName(transaction.category, transaction.type))
        : transaction.categoryId;

    try {
      await _apiClient.createTransaction(
        amount: transaction.amount,
        type: _transactionTypeToApi(transaction.type),
        occurredOn: transaction.occurredOn,
        currency: transaction.currency,
        kind: _transactionKindToApi(transaction.kind),
        categoryId: categoryId,
        budgetId: transaction.budgetId,
        note: _encodeNotePayload(transaction),
      );

      await _loadTransactions();
      await _loadBudgets();
      await _loadSummary(currentUser);
      summary ??= _buildLocalSummary();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      }
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Tworzy nowy cel oszczędnościowy i przeładowuje ich listę.
  /// Zwraca informację o powodzeniu dla UI.
  Future<bool> createSavingsGoal({
    required String name,
    required double targetAmount,
    double initialAmount = 0,
    DateTime? deadline,
    int? categoryId,
  }) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    dataError = null;
    notifyListeners();

    try {
      await _apiClient.createSavingsGoal(
        name: name,
        targetAmount: targetAmount,
        initialAmount: initialAmount,
        deadline: deadline,
        categoryId: categoryId,
      );
      await _loadSavingsGoals();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      dataError = 'Nie udało się utworzyć celu oszczędnościowego.';
      notifyListeners();
      return false;
    }
  }

  /// Dodaje wpłatę do istniejącego celu i aktualizuje podsumowanie.
  /// Po sukcesie odświeża cele i podsumowanie.
  Future<bool> addSavingsContribution({
    required int goalId,
    required double amount,
    String? note,
  }) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    dataError = null;
    notifyListeners();

    try {
      await _apiClient.addSavingsContribution(
        goalId: goalId,
        amount: amount,
        note: note,
      );
      await _loadSavingsGoals();
      await _loadSummary(currentUser);
      summary ??= _buildLocalSummary();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      dataError = 'Nie udało się dodać wpłaty.';
      notifyListeners();
      return false;
    }
  }

  /// Usuwa cel oszczędnościowy i odświeża listę celów oraz podsumowanie.
  /// Obsługuje błędy autoryzacji i komunikaty dla UI.
  Future<bool> deleteSavingsGoal(int goalId) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    dataError = null;
    notifyListeners();

    try {
      await _apiClient.deleteSavingsGoal(goalId: goalId);
      await _loadSavingsGoals();
      await _loadSummary(currentUser);
      summary ??= _buildLocalSummary();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      dataError = 'Nie udało się usunąć celu oszczędnościowego.';
      notifyListeners();
      return false;
    }
  }

  /// Tworzy nową kategorię wydatku i ustawia ją jako wybraną po sukcesie.
  /// Zwraca utworzoną kategorię lub `null` przy błędzie.
  Future<CategoryItem?> createExpenseCategory(String name) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return null;
    }

    dataError = null;
    notifyListeners();

    try {
      final rawCategory = await _apiClient.createCategory(name: name);
      await _loadCategories();
      return _mapCategory(rawCategory);
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return null;
    } catch (_) {
      dataError = 'Nie udało się utworzyć kategorii.';
      notifyListeners();
      return null;
    }
  }

  /// Usuwa kategorię z backendu na stałe i odświeża dane.
  /// Zwraca `false`, gdy użytkownik nie jest zalogowany.
  Future<bool> deleteCategory(int categoryId) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    dataError = null;
    notifyListeners();

    try {
      await _apiClient.deleteCategory(categoryId: categoryId);
      await _loadCategories();
      await _loadBudgets();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      dataError = 'Nie udało się usunąć kategorii.';
      notifyListeners();
      return false;
    }
  }

  /// Tworzy nowy własny rodzaj budżetu i odświeża listę.
  /// Zwraca utworzony typ lub `null` przy błędzie.
  Future<BudgetTypeItem?> createBudgetType(String name) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return null;
    }

    dataError = null;
    notifyListeners();

    try {
      final rawType = await _apiClient.createBudgetType(name: name);
      await _loadBudgetTypes();
      return _mapBudgetType(rawType);
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return null;
    } catch (_) {
      dataError = 'Nie udało się utworzyć rodzaju budżetu.';
      notifyListeners();
      return null;
    }
  }

  /// Usuwa własny rodzaj budżetu i odświeża listę.
  /// Utrzymuje spójność listy typów w UI.
  Future<bool> deleteBudgetType(int typeId) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    dataError = null;
    notifyListeners();

    try {
      await _apiClient.deleteBudgetType(id: typeId);
      await _loadBudgetTypes();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      dataError = 'Nie udało się usunąć rodzaju budżetu.';
      notifyListeners();
      return false;
    }
  }

  /// Zakłada budżet w backendzie, a potem odświeża listę i podsumowanie.
  /// Zwraca `true`, gdy operacja przebiegła pomyślnie.
  Future<bool> createBudget({
    required String name,
    required double limitAmount,
    String period = 'monthly',
    String budgetType = 'custom',
    int? categoryId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final currentUser = user;
    if (!isAuthenticated || currentUser == null) {
      return false;
    }

    isLoading = true;
    dataError = null;
    notifyListeners();

    try {
      await _apiClient.createBudget(
        name: name,
        limitAmount: limitAmount,
        period: period,
        budgetType: budgetType,
        categoryId: categoryId,
        startDate: startDate,
        endDate: endDate,
      );

      await _loadBudgets();
      await _loadSummary(currentUser);
      summary ??= _buildLocalSummary();
      return true;
    } on SavooApiException catch (error) {
      dataError = error.message;
      if (error.statusCode == 401) {
        await logout();
      }
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

/// Pomocniczy model rozpakowujący JSON notatki transakcji.
class _NoteDetails {
  /// Tworzy kontener na szczegóły notatki transakcji.
  /// Przechowuje tytuł, opis i flagę auto-przychodu.
  const _NoteDetails({this.title, this.note, this.isAutoIncome = false});

  final String? title;
  final String? note;
  final bool isAutoIncome;
}
