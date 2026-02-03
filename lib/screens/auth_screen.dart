import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/savoo_api_client.dart';
import '../state/app_state.dart';

const List<Map<String, String>> _securityQuestionOptions = [
  {'key': 'pet_name', 'label': 'Imię Twojego pupila'},
  {
    'key': 'childhood_friend',
    'label': 'Imię najlepszego przyjaciela z dzieciństwa',
  },
  {'key': 'birth_city', 'label': 'Miasto urodzenia Twojej mamy'},
  {'key': 'favorite_teacher', 'label': 'Imię ulubionego nauczyciela'},
  {'key': 'first_school', 'label': 'Nazwa Twojej pierwszej szkoły'},
];

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  /// Buduje ekran logowania/rejestracji z formularzem i przyciskami akcji.
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _securityAnswerController = TextEditingController();

  bool _isLoginMode = true;
  String? _selectedSecurityQuestionKey;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _securityAnswerController.dispose();
    super.dispose();
  }

  /// Przełącza formularz między logowaniem a rejestracją.
  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _selectedSecurityQuestionKey = null;
      _securityAnswerController.clear();
    });
  }

  /// Waliduje formularz i uruchamia logowanie albo rejestrację.
  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();
    final securityAnswer = _securityAnswerController.text.trim();
    final securityQuestionKey = _selectedSecurityQuestionKey;

    if (!_isLoginMode &&
        (securityQuestionKey == null || securityQuestionKey.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz pytanie bezpieczeństwa.')),
      );
      return;
    }

    final appState = context.read<AppState>();
    final success = _isLoginMode
        ? await appState.login(email, password)
        : await appState.register(
            email,
            password,
            displayName,
            securityQuestionKey: securityQuestionKey!,
            securityAnswer: securityAnswer,
          );

    if (!mounted) return;

    if (!success) {
      final message = appState.authError ?? 'Wystąpił błąd. Spróbuj ponownie.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } else if (_isLoginMode) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Zalogowano pomyślnie.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konto utworzone. Zalogowano.')),
      );
    }
  }

  /// Otwiera dialog resetu hasła z dwuetapową weryfikacją.
  Future<void> _showForgotPasswordDialog() async {
    final appState = context.read<AppState>();
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final questionAnswerController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? dialogQuestionKey;
    String? resetToken;
    String? errorMessage;
    bool isSubmitting = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final isVerificationStep = resetToken == null;

              Future<void> handleSubmit() async {
                if (isSubmitting) return;
                setDialogState(() {
                  isSubmitting = true;
                  errorMessage = null;
                });
                final email = emailController.text.trim().toLowerCase();
                if (email.isEmpty) {
                  setDialogState(() {
                    errorMessage = 'Podaj adres e-mail powiązany z kontem.';
                    isSubmitting = false;
                  });
                  return;
                }

                try {
                  if (isVerificationStep) {
                    final questionKey = dialogQuestionKey;
                    final answer = questionAnswerController.text.trim();
                    if (questionKey == null || questionKey.isEmpty) {
                      setDialogState(() {
                        errorMessage = 'Wybierz pytanie bezpieczeństwa.';
                        isSubmitting = false;
                      });
                      return;
                    }
                    if (answer.length < 3) {
                      setDialogState(() {
                        errorMessage = 'Odpowiedź musi mieć min. 3 znaki.';
                        isSubmitting = false;
                      });
                      return;
                    }
                    final token = await appState.requestPasswordResetToken(
                      email: email,
                      securityQuestionKey: questionKey,
                      securityAnswer: answer,
                    );
                    setDialogState(() {
                      resetToken = token;
                      isSubmitting = false;
                    });
                  } else {
                    final newPassword = newPasswordController.text;
                    final confirmPassword = confirmPasswordController.text;
                    if (newPassword.length < 6 ||
                        !RegExp(r'[A-Za-z]').hasMatch(newPassword) ||
                        !RegExp(r'\d').hasMatch(newPassword)) {
                      setDialogState(() {
                        errorMessage =
                            'Hasło musi mieć 6 znaków oraz zawierać literę i cyfrę.';
                        isSubmitting = false;
                      });
                      return;
                    }
                    if (newPassword != confirmPassword) {
                      setDialogState(() {
                        errorMessage = 'Hasła muszą być identyczne.';
                        isSubmitting = false;
                      });
                      return;
                    }
                    final token = resetToken!;
                    await appState.resetPasswordWithToken(
                      email: email,
                      resetToken: token,
                      newPassword: newPassword,
                      confirmPassword: confirmPassword,
                    );
                    if (!dialogContext.mounted || !mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Hasło zostało zresetowane. Zaloguj się.',
                        ),
                      ),
                    );
                  }
                } on SavooApiException catch (error) {
                  setDialogState(() {
                    errorMessage = error.message;
                    isSubmitting = false;
                  });
                } catch (_) {
                  setDialogState(() {
                    errorMessage = 'Nie udało się przetworzyć żądania.';
                    isSubmitting = false;
                  });
                }
              }

              return AlertDialog(
                title: Text(
                  isVerificationStep
                      ? 'Zweryfikuj pytanie bezpieczeństwa'
                      : 'Ustaw nowe hasło',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: emailController,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Adres e-mail',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      if (isVerificationStep) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(dialogQuestionKey ?? 'none'),
                          initialValue: dialogQuestionKey,
                          isExpanded: true,
                          items: _securityQuestionOptions
                              .map(
                                (option) => DropdownMenuItem<String>(
                                  value: option['key'],
                                  child: Text(option['label'] ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: isSubmitting
                              ? null
                              : (value) => setDialogState(() {
                                  dialogQuestionKey = value;
                                }),
                          decoration: const InputDecoration(
                            labelText: 'Twoje pytanie bezpieczeństwa',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: questionAnswerController,
                          enabled: !isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'Odpowiedź',
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: newPasswordController,
                          enabled: !isSubmitting,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Nowe hasło',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmPasswordController,
                          enabled: !isSubmitting,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Powtórz hasło',
                          ),
                        ),
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Anuluj'),
                  ),
                  FilledButton(
                    onPressed: isSubmitting ? null : handleSubmit,
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isVerificationStep ? 'Dalej' : 'Zapisz hasło'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      emailController.dispose();
      questionAnswerController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
  }

  /// Renderuje kartę logowania/rejestracji
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final isBusy = appState.authInProgress;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.savings_outlined,
                          size: 54,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isLoginMode
                              ? 'Zaloguj się do Savoo'
                              : 'Załóż konto w Savoo',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _emailController,
                          enabled: !isBusy,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Adres e-mail',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) {
                              return 'Podaj adres e-mail.';
                            }
                            final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                            if (!regex.hasMatch(email)) {
                              return 'Wpisz poprawny adres e-mail.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        if (!_isLoginMode)
                          TextFormField(
                            controller: _displayNameController,
                            enabled: !isBusy,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Imię (wyświetlane)',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (_isLoginMode) {
                                return null;
                              }
                              if ((value ?? '').trim().isEmpty) {
                                return 'Podaj imię, które chcemy wyświetlać w aplikacji.';
                              }
                              return null;
                            },
                          ),
                        if (!_isLoginMode) const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !isBusy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Hasło',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.length < 6) {
                              return 'Hasło musi mieć co najmniej 6 znaków.';
                            }
                            if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
                                !RegExp(r'\d').hasMatch(password)) {
                              return 'Hasło musi zawierać literę i cyfrę.';
                            }
                            return null;
                          },
                        ),
                        if (!_isLoginMode) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              _selectedSecurityQuestionKey ?? 'none',
                            ),
                            initialValue: _selectedSecurityQuestionKey,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Pytanie bezpieczeństwa',
                              prefixIcon: Icon(Icons.security_outlined),
                            ),
                            items: _securityQuestionOptions
                                .map(
                                  (option) => DropdownMenuItem<String>(
                                    value: option['key'],
                                    child: Text(option['label'] ?? ''),
                                  ),
                                )
                                .toList(),
                            onChanged: isBusy
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedSecurityQuestionKey = value;
                                    });
                                  },
                            validator: (_) {
                              if (_isLoginMode) {
                                return null;
                              }
                              if ((_selectedSecurityQuestionKey ?? '')
                                  .isEmpty) {
                                return 'Wybierz pytanie bezpieczeństwa.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _securityAnswerController,
                            enabled: !isBusy,
                            decoration: const InputDecoration(
                              labelText: 'Odpowiedź na pytanie',
                              prefixIcon: Icon(Icons.edit_note_outlined),
                            ),
                            validator: (value) {
                              if (_isLoginMode) {
                                return null;
                              }
                              final answer = (value ?? '').trim();
                              if (answer.length < 3) {
                                return 'Odpowiedź musi mieć co najmniej 3 znaki.';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: isBusy ? null : _submit,
                          icon: isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _isLoginMode
                                      ? Icons.login
                                      : Icons.app_registration,
                                ),
                          label: Text(
                            _isLoginMode ? 'Zaloguj się' : 'Zarejestruj się',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: isBusy ? null : _toggleMode,
                          child: Text(
                            _isLoginMode
                                ? 'Nie masz konta? Zarejestruj się'
                                : 'Masz już konto? Zaloguj się',
                          ),
                        ),
                        if (_isLoginMode)
                          TextButton(
                            onPressed: isBusy
                                ? null
                                : _showForgotPasswordDialog,
                            child: const Text('Nie pamiętasz hasła?'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
