import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/savoo_api_client.dart';
import 'state/app_state.dart';
import 'widgets/restart_app.dart';

/// Uruchamia Fluttera po wcześniejszym zainicjalizowaniu powiązań platformowych.
/// Ustawia korzeń aplikacji z mechanizmem restartu.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RestartApp(child: SavooApp()));
}

class SavooApp extends StatelessWidget {
  /// Tworzy główny widżet aplikacji z motywem i providerem stanu.
  const SavooApp({super.key});

  /// Buduje globalny `MaterialApp` z motywem, stanem aplikacji i ekranem startowym.
  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF16A085),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    final textTheme = GoogleFonts.poppinsTextTheme(baseTheme.textTheme);

    return ChangeNotifierProvider(
      create: (_) => AppState(SavooApiClient())..bootstrap(),
      child: MaterialApp(
        title: 'Savoo',
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          textTheme: textTheme,
          splashFactory: InkRipple.splashFactory,
          appBarTheme: baseTheme.appBarTheme.copyWith(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: baseTheme.colorScheme.onSurface,
          ),
        ),
        home: const SavooRoot(),
      ),
    );
  }
}

class SavooRoot extends StatelessWidget {
  /// Buduje korzeń nawigacji zależny od stanu logowania.
  const SavooRoot({super.key});

  /// Wybiera odpowiednią gałąź UI w zależności od tego, czy stan został zainicjalizowany i zalogowany.
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        if (appState.isBootstrapping) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!appState.isAuthenticated) {
          return const AuthScreen();
        }

        return const HomeShell();
      },
    );
  }
}
