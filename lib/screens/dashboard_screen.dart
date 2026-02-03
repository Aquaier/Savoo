import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/summary_card.dart';
import '../widgets/budget_progress_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  /// Pokazuje skrócony przegląd finansów użytkownika wraz z kartami i listami.
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final summary = appState.summary;
        if (summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = appState.user;
        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: appState.refreshDashboard,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                pinned: false,
                floating: false,
                title: Text(
                  'Cześć, ${user?.displayName ?? 'Savoo'}',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: CircleAvatar(child: Icon(Icons.savings_rounded)),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                sliver: SliverList.list(
                  children: [
                    SummaryCard(
                      netSavings: summary.netSavings,
                      currency: user?.defaultCurrency ?? 'PLN',
                      totalIncome: summary.totalIncome,
                      totalExpense: summary.totalExpense,
                      isLoading: appState.isLoading,
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(title: 'Najczęstsze kategorie wydatków'),
                    const SizedBox(height: 12),
                    if (summary.topExpenseCategories.isEmpty)
                      Text(
                        'Brak wydatków.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      ...summary.topExpenseCategories
                          .take(2)
                          .map(
                            (category) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _CategoryTile(
                                name: category.name,
                                value: category.spent,
                                currency: user?.defaultCurrency ?? 'PLN',
                              ),
                            ),
                          ),
                    const SizedBox(height: 28),
                    _SectionTitle(title: 'Moje Budżety'),
                    const SizedBox(height: 12),
                    ...appState.budgets.map(
                      (budget) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BudgetProgressCard(budget: budget),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  /// Renderuje nagłówek sekcji z jednolitym stylem czcionki.
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.value,
    required this.currency,
  });

  final String name;
  final double value;
  final String currency;

  /// Pokazuje kafelek z nazwą kategorii i sumą wydatków.
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.category),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(0)} $currency',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
