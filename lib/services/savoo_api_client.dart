import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SavooApiException implements Exception {
  /// Tworzy wyjątek API z komunikatem
  /// Używany do przekazywania błędów z backendu do warstwy UI.
  SavooApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Zwraca opis błędu wraz z kodem HTTP.
  @override
  String toString() =>
      'SavooApiException(statusCode: $statusCode, message: $message)';
}

class SavooApiClient {
  /// Tworzy klienta HTTP z możliwością wstrzyknięcia bazowego URL i klienta.
  SavooApiClient({http.Client? httpClient, String? baseUrl})
    : _client = httpClient ?? http.Client(),
      baseUrl = baseUrl ?? _resolveBaseUrl();

  final http.Client _client;
  final String baseUrl;

  String? _authHeader;
  String? _currentEmail;

  static String _resolveBaseUrl() {
    if (kIsWeb) {
      return 'http://localhost:5001';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:5001';
      default:
        return 'http://localhost:5001';
    }
  }

  /// Zapamiętuje dane logowania i ustawia nagłówek Basic Auth dla kolejnych żądań.
  void updateSession({required String email, required String password}) {
    final encoded = base64Encode(utf8.encode('$email:$password'));
    _authHeader = 'Basic $encoded';
    _currentEmail = email;
  }

  /// Czyści sesję HTTP oraz nagłówki autoryzacyjne po wylogowaniu lub błędzie autoryzacji.
  void clearSession() {
    _authHeader = null;
    _currentEmail = null;
  }

  /// Loguje użytkownika i zwraca payload odpowiedzi backendu.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      _buildUri('/login'),
      headers: _headers(auth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    return data as Map<String, dynamic>;
  }

  /// Rejestruje nowego użytkownika i zwraca dane sesji.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
    required String securityQuestionKey,
    required String securityAnswer,
  }) async {
    final response = await _client.post(
      _buildUri('/register'),
      headers: _headers(auth: false),
      body: jsonEncode({
        'email': email,
        'password': password,
        'display_name': displayName,
        'security_question_key': securityQuestionKey,
        'security_answer': securityAnswer,
      }),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    return data as Map<String, dynamic>;
  }

  /// Rozpoczyna procedurę resetu hasła, weryfikując pytanie bezpieczeństwa.
  Future<String> startPasswordReset({
    required String email,
    required String securityQuestionKey,
    required String securityAnswer,
  }) async {
    final response = await _client.post(
      _buildUri('/forgot-password/verify'),
      headers: _headers(auth: false),
      body: jsonEncode({
        'email': email,
        'security_question_key': securityQuestionKey,
        'security_answer': securityAnswer,
      }),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic> && data['success'] == true) {
      final token = data['reset_token']?.toString();
      if (token != null && token.isNotEmpty) {
        return token;
      }
    }
    throw SavooApiException(
      'Nie udało się wygenerować tokenu resetu hasła.',
      statusCode: response.statusCode,
    );
  }

  /// Kończy procedurę resetu hasła po poprawnej odpowiedzi na pytanie.
  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await _client.post(
      _buildUri('/forgot-password/reset'),
      headers: _headers(auth: false),
      body: jsonEncode({
        'email': email,
        'reset_token': resetToken,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      }),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się zresetować hasła.',
    );
  }

  /// Aktualizuje podstawowe parametry profilu (waluta, dochód, nazwa).
  Future<void> updateProfile({
    required String displayName,
    required String defaultCurrency,
    double? monthlyIncome,
    String? monthlyIncomeCurrency,
    int? monthlyIncomeDay,
  }) async {
    final payload = <String, dynamic>{
      'display_name': displayName,
      'default_currency': defaultCurrency,
      'monthly_income_day': monthlyIncomeDay,
    };
    if (monthlyIncome != null) {
      payload['monthly_income'] = monthlyIncome;
    }
    if (monthlyIncomeCurrency != null) {
      payload['monthly_income_currency'] = monthlyIncomeCurrency;
    }

    final response = await _client.put(
      _buildUri('/profile'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się zaktualizować profilu.',
    );
  }

  /// Pobiera bieżący profil zalogowanego użytkownika.
  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await _client.get(
      _buildUri('/profile'),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się pobrać profilu.',
    );
    if (data is Map<String, dynamic> &&
        data['profile'] is Map<String, dynamic>) {
      return data['profile'] as Map<String, dynamic>;
    }
    throw SavooApiException('Nieprawidłowa odpowiedź serwera.');
  }

  Future<void> logout() async {
    if (_authHeader == null) {
      clearSession();
      return;
    }
    final response = await _client.post(
      _buildUri('/logout'),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się wylogować.',
    );
    clearSession();
  }

  /// Pobiera wszystkie dane użytkownika w formacie CSV.
  Future<List<int>> exportAllDataCsv() async {
    final response = await _client.get(
      _buildUri('/export/all'),
      headers: _headers(),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }

    String message = 'Nie udało się pobrać danych.';
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['message'] != null) {
        message = data['message'].toString();
      }
    } catch (_) {}
    throw SavooApiException(message, statusCode: response.statusCode);
  }

  /// Pobiera podsumowanie finansowe pulpitu dla wskazanego użytkownika.
  Future<Map<String, dynamic>?> fetchSummary(String email) async {
    final uri = _buildUri(
      '/dashboard/summary',
      queryParameters: {'email': email, 'period': 'monthly'},
    );
    final response = await _client.get(uri, headers: _headers());
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic> && data['success'] == true) {
      return data['summary'] as Map<String, dynamic>?;
    }
    return null;
  }

  /// Ściąga listę kategorii wydatków/przychodów.
  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final response = await _client.get(
      _buildUri('/categories'),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic>) {
      final raw = data['categories'] as List<dynamic>? ?? const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Tworzy nową kategorię w backendzie i zwraca jej dane.
  Future<Map<String, dynamic>> createCategory({
    required String name,
    String type = 'expense',
    String? color,
    String? iconUrl,
  }) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }
    final payload = <String, dynamic>{
      'email': email,
      'name': name,
      'type': type,
      if (color != null) 'color': color,
      if (iconUrl != null) 'icon_url': iconUrl,
    };

    final response = await _client.post(
      _buildUri('/categories'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się utworzyć kategorii.',
    );

    if (data is Map<String, dynamic> && data['category'] is Map) {
      final raw = (data['category'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return raw.cast<String, dynamic>();
    }

    return {
      'id': null,
      'name': name,
      'type': type,
      'color': color,
      'icon_url': iconUrl,
    };
  }

  /// Usuwa kategorię z backendu na stałe.
  Future<void> deleteCategory({required int categoryId}) async {
    final response = await _client.delete(
      _buildUri('/categories/$categoryId'),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się usunąć kategorii.',
    );
  }

  /// Pobiera wszystkie transakcje użytkownika.
  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    final response = await _client.get(
      _buildUri('/transactions'),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic>) {
      final raw = data['transactions'] as List<dynamic>? ?? const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Dodaje nową transakcję (wydatek/zasilenie) w backendzie.
  Future<void> createTransaction({
    required double amount,
    required String type,
    required DateTime occurredOn,
    required String currency,
    String kind = 'general',
    int? categoryId,
    int? budgetId,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'amount': amount,
      'type': type,
      'occurred_on': occurredOn.toIso8601String(),
      'currency': currency,
      'kind': kind,
      if (categoryId != null) 'category_id': categoryId,
      if (budgetId != null) 'budget_id': budgetId,
      if (note != null && note.isNotEmpty) 'note': note,
    };

    final response = await _client.post(
      _buildUri('/transactions'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się dodać transakcji.',
    );
  }

  /// Pobiera listę budżetów powiązanych z aktualnym użytkownikiem.
  Future<List<Map<String, dynamic>>> fetchBudgets() async {
    final email = _currentEmail;
    if (email == null || email.isEmpty) {
      return const [];
    }
    final response = await _client.get(
      _buildUri('/budgets', queryParameters: {'email': email}),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic>) {
      final raw = data['budgets'] as List<dynamic>? ?? const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Zakłada nowy budżet o podanych limitach
  Future<void> createBudget({
    required String name,
    required double limitAmount,
    String period = 'monthly',
    String budgetType = 'custom',
    int? categoryId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }
    final payload = <String, dynamic>{
      'email': email,
      'name': name,
      'limit_amount': limitAmount,
      'period': period,
      'budget_type': budgetType,
      if (categoryId != null) 'category_id': categoryId,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
    };
    final response = await _client.post(
      _buildUri('/budgets'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się utworzyć budżetu.',
    );
  }

  /// Pobiera listę własnych rodzajów budżetów użytkownika.
  Future<List<Map<String, dynamic>>> fetchBudgetTypes() async {
    final email = _currentEmail;
    if (email == null || email.isEmpty) {
      return const [];
    }
    final response = await _client.get(
      _buildUri('/budget-types', queryParameters: {'email': email}),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic>) {
      final raw = data['budget_types'] as List<dynamic>? ?? const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Tworzy nowy własny rodzaj budżetu.
  Future<Map<String, dynamic>> createBudgetType({required String name}) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }
    final payload = <String, dynamic>{'email': email, 'name': name};
    final response = await _client.post(
      _buildUri('/budget-types'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się dodać rodzaju budżetu.',
    );
    if (data is Map<String, dynamic>) {
      return (data['budget_type'] as Map?)?.cast<String, dynamic>() ?? {};
    }
    return {};
  }

  /// Usuwa wskazany rodzaj budżetu.
  Future<void> deleteBudgetType({required int id}) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }
    final response = await _client.delete(
      _buildUri('/budget-types/$id', queryParameters: {'email': email}),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się usunąć rodzaju budżetu.',
    );
  }

  /// Pobiera listę celów oszczędnościowych dla bieżącego konta.
  Future<List<Map<String, dynamic>>> fetchSavingsGoals() async {
    final email = _currentEmail;
    if (email == null) {
      return const [];
    }
    final response = await _client.get(
      _buildUri('/savings-goals', queryParameters: {'email': email}),
      headers: _headers(),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(response.statusCode, data);
    if (data is Map<String, dynamic>) {
      final raw = data['goals'] as List<dynamic>? ?? const [];
      return raw
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Tworzy nowy cel oszczędnościowy z opcjonalnym deadlinem.
  Future<void> createSavingsGoal({
    required String name,
    required double targetAmount,
    double initialAmount = 0,
    DateTime? deadline,
    int? categoryId,
  }) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }
    final payload = <String, dynamic>{
      'email': email,
      'name': name,
      'target_amount': targetAmount,
      'current_amount': initialAmount,
      if (deadline != null) 'deadline': deadline.toIso8601String(),
      if (categoryId != null) 'category_id': categoryId,
    };

    final response = await _client.post(
      _buildUri('/savings-goals'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się utworzyć celu oszczędnościowego.',
    );
  }

  /// Usuwa wskazany cel oszczędnościowy.
  Future<void> deleteSavingsGoal({required int goalId}) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }

    final response = await _client.delete(
      _buildUri('/savings-goals/$goalId'),
      headers: _headers(),
      body: jsonEncode({'email': email}),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się usunąć celu oszczędnościowego.',
    );
  }

  /// Dodaje wpłatę do istniejącego celu oszczędnościowego.
  Future<void> addSavingsContribution({
    required int goalId,
    required double amount,
    String? note,
  }) async {
    final email = _currentEmail;
    if (email == null) {
      throw SavooApiException('Brak zalogowanego użytkownika.');
    }
    final payload = <String, dynamic>{
      'email': email,
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
    };

    final response = await _client.post(
      _buildUri('/savings-goals/$goalId/contributions'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    _ensureSuccess(
      response.statusCode,
      data,
      fallbackMessage: 'Nie udało się dodać wpłaty.',
    );
  }

  /// Buduje nagłówki żądania wraz z autoryzacją
  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final authHeader = _authHeader;
    if (auth && authHeader != null && authHeader.isNotEmpty) {
      headers['Authorization'] = authHeader;
    }
    return headers;
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '$baseUrl$normalizedPath',
    ).replace(queryParameters: queryParameters);
  }

  /// Dekoduje odpowiedź JSON lub rzuca wyjątek przy błędnym formacie.
  dynamic _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw SavooApiException(
        'Nieprawidłowa odpowiedź serwera.',
        statusCode: response.statusCode,
      );
    }
  }

  /// Sprawdza kod statusu i ewentualnie rzuca `SavooApiException`.
  void _ensureSuccess(
    int statusCode,
    dynamic data, {
    String fallbackMessage = 'Operacja nie powiodła się.',
  }) {
    final success = statusCode >= 200 && statusCode < 300;
    if (success) {
      if (data is Map<String, dynamic> &&
          data.containsKey('success') &&
          data['success'] == false) {
        final message = data['message']?.toString() ?? fallbackMessage;
        throw SavooApiException(message, statusCode: statusCode);
      }
      return;
    }

    final message =
        (data is Map<String, dynamic> ? data['message']?.toString() : null) ??
        fallbackMessage;
    throw SavooApiException(message, statusCode: statusCode);
  }

  /// Udostępnia adres e-mail aktualnie zalogowanego użytkownika.
  String? get currentEmail => _currentEmail;
}
