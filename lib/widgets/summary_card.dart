import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SummaryCard extends StatelessWidget {
  /// Buduje kartę podsumowania z przekazanymi wartościami i walutą.
  const SummaryCard({
    super.key,
    required this.netSavings,
    required this.currency,
    required this.totalIncome,
    required this.totalExpense,
    this.isLoading = false,
  });

  final double netSavings;
  final String currency;
  final double totalIncome;
  final double totalExpense;
  final bool isLoading;

  /// Renderuje kartę z bilansem miesiąca i kafelkami przychodów/wydatków.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gradient = LinearGradient(
      colors: [colorScheme.primary, colorScheme.primaryContainer],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bilans miesiąca',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.center,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
          const SizedBox(height: 8),
          _SummaryTile(
            label: 'Przychody',
            value: totalIncome,
            currency: currency,
            icon: Icons.arrow_upward,
            color: Colors.tealAccent.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 12),
          _SummaryTile(
            label: 'Wydatki',
            value: totalExpense,
            currency: currency,
            icon: Icons.arrow_downward,
            color: Colors.deepOrangeAccent.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 12),
          _SummaryTile(
            label: 'Oszczędności',
            value: netSavings,
            currency: currency,
            icon: Icons.savings_rounded,
            color: Colors.indigoAccent.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  /// Tworzy kafelek z etykietą, ikoną i wartością w danej walucie.
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.currency,
    required this.icon,
    required this.color,
  });

  final String label;
  final double value;
  final String currency;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${value.toStringAsFixed(0)} $currency',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
