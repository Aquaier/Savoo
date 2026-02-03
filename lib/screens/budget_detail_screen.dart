import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/iconography.dart';

class BudgetDetailScreen extends StatefulWidget {
  const BudgetDetailScreen({super.key, required this.budget});

  final BudgetItem budget;

  /// Tworzy stan odpowiedzialny za prezentację szczegółów i wykresów budżetu.
  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

enum _BudgetChartInterval { daily, weekly, monthly }

enum _BudgetChartMode { cumulative, perPeriod }

const Map<_BudgetChartInterval, String> _intervalLabels = {
  _BudgetChartInterval.daily: 'Dzień po dniu',
  _BudgetChartInterval.weekly: 'Tydzień po tygodniu',
  _BudgetChartInterval.monthly: 'Miesiąc po miesiącu',
};

const Map<_BudgetChartMode, String> _modeLabels = {
  _BudgetChartMode.cumulative: 'Narastająco',
  _BudgetChartMode.perPeriod: 'Wydatki w okresie',
};

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  late _BudgetChartInterval _interval;
  late _BudgetChartMode _mode;
  late DateTimeRange _range;
  late DateTimeRange _defaultRange;
  bool _localeReady = false;

  /// Ustawia początkowe filtry osi czasu
  @override
  void initState() {
    super.initState();
    _interval = _BudgetChartInterval.daily;
    _mode = _BudgetChartMode.cumulative;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initializeDateFormatting('pl_PL', null);
      if (!mounted) {
        return;
      }
      setState(() {
        _localeReady = true;
      });
    });

    final now = DateTime.now();
    final normalizedEnd = DateTime(now.year, now.month, now.day);
    final normalizedStart = normalizedEnd.subtract(const Duration(days: 30));

    _defaultRange = DateTimeRange(start: normalizedStart, end: normalizedEnd);
    _range = _defaultRange;
  }

  /// Buduje ekran z nagłówkiem, filtrami, wykresem i statystykami budżetu.
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final currency = appState.user?.defaultCurrency ?? 'PLN';
    final series = _buildSeries(appState.transactions);
    final points = series.points;
    final effectiveRange = _clampRangeToToday(_range);

    final gradientBackground = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceContainerHigh,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: theme.brightness,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        title: Text(
          'Budżet: ${widget.budget.name}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          gradientBackground,
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                _buildHeader(theme, currency),
                const SizedBox(height: 20),
                _buildFilters(theme),
                const SizedBox(height: 20),
                _buildChartCard(theme, points),
                const SizedBox(height: 16),
                _buildStatistics(theme, currency, series, effectiveRange),
                if (points.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Brak wydatków dla wybranego zakresu. Zmień filtr lub dodaj transakcje.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tworzy sekcję nagłówka z metadanymi budżetu i podstawowymi liczbami.
  Widget _buildHeader(ThemeData theme, String currency) {
    const budgetTypeLabels = {
      'household': 'Budżet domowy',
      'entertainment': 'Rozrywka',
      'groceries': 'Zakupy',
      'travel': 'Podróże',
      'savings': 'Oszczędności',
      'health': 'Zdrowie',
      'education': 'Edukacja',
      'custom': 'Własny budżet',
    };

    const periodLabels = {
      'weekly': 'Tygodniowy',
      'monthly': 'Miesięczny',
      'quarterly': 'Kwartalny',
      'custom': 'Niestandardowy',
    };

    final colorScheme = theme.colorScheme;
    final rawType = widget.budget.budgetType;
    final typeLabel =
        budgetTypeLabels[rawType] ?? _formatBudgetTypeLabel(rawType);
    final periodLabel =
        periodLabels[widget.budget.period] ?? widget.budget.period;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconForBudgetType(widget.budget.budgetType),
              size: 28,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.budget.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$typeLabel • $periodLabel',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Limit: ${_formatAmount(widget.budget.limitAmount)} $currency',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wydano: ${_formatAmount(widget.budget.spentAmount)} $currency',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.budget.remaining >= 0
                      ? 'Pozostało: ${_formatAmount(widget.budget.remaining)} $currency'
                      : 'Przekroczono: ${_formatAmount(widget.budget.remaining.abs())} $currency',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widget.budget.remaining >= 0
                        ? colorScheme.primary
                        : colorScheme.error,
                  ),
                ),
                if (widget.budget.startDate != null ||
                    widget.budget.endDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (widget.budget.startDate != null)
                          _buildInfoChip(
                            theme,
                            Icons.play_arrow_rounded,
                            'Start: ${DateFormat('dd.MM.yyyy').format(widget.budget.startDate!)}',
                          ),
                        if (widget.budget.endDate != null)
                          _buildInfoChip(
                            theme,
                            Icons.flag_outlined,
                            'Koniec: ${DateFormat('dd.MM.yyyy').format(widget.budget.endDate!)}',
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBudgetTypeLabel(String value) {
    if (value.trim().isEmpty) {
      return 'Budżet niestandardowy';
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

  /// Rysuje zestaw kontrolek służących do zmiany zakresu
  Widget _buildFilters(ThemeData theme) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 340),
          child: DropdownButtonFormField<_BudgetChartInterval>(
            isExpanded: true,
            initialValue: _interval,
            decoration: const InputDecoration(
              labelText: 'Oś X',
              prefixIcon: Icon(Icons.timeline_outlined),
            ),
            items: _BudgetChartInterval.values
                .map(
                  (interval) => DropdownMenuItem<_BudgetChartInterval>(
                    value: interval,
                    child: Text(
                      _intervalLabels[interval]!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _interval = value);
            },
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 340),
          child: DropdownButtonFormField<_BudgetChartMode>(
            isExpanded: true,
            initialValue: _mode,
            decoration: const InputDecoration(
              labelText: 'Oś Y',
              prefixIcon: Icon(Icons.stacked_line_chart),
            ),
            items: _BudgetChartMode.values
                .map(
                  (mode) => DropdownMenuItem<_BudgetChartMode>(
                    value: mode,
                    child: Text(
                      _modeLabels[mode]!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _mode = value);
            },
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.date_range),
          label: Text(_formatRangeLabel(_range)),
        ),
        TextButton(
          onPressed: _isCustomRange
              ? () => setState(() => _range = _defaultRange)
              : null,
          child: const Text('Resetuj zakres'),
        ),
      ],
    );
  }

  /// Zawija wykres w kartę i pokazuje placeholder, gdy jest brak danych.
  Widget _buildChartCard(ThemeData theme, List<_ChartPoint> points) {
    final colorScheme = theme.colorScheme;
    final hasValidData = points.any((point) => point.value > 0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: SizedBox(
        height: 280,
        child: !hasValidData
            ? Center(
                child: Text(
                  points.isEmpty
                      ? 'Brak danych do wyświetlenia.'
                      : 'Brak danych do wyświetlenia w okresie',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : _buildLineChart(theme, points),
      ),
    );
  }

  /// Konfiguruje `LineChart` na podstawie przygotowanych punktów serii.
  Widget _buildLineChart(ThemeData theme, List<_ChartPoint> points) {
    if (!_localeReady) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x));
    final chartPoints = sorted
        .map((point) => FlSpot(point.x, point.value))
        .toList();
    var minX = sorted.first.x;
    var maxX = sorted.last.x;
    if (minX == maxX) {
      maxX = minX + 1;
      chartPoints.add(FlSpot(maxX, sorted.last.value));
    }

    final maxYValue = chartPoints.fold<double>(
      0,
      (current, spot) => max(current, spot.y),
    );
    final rawMaxY = maxYValue == 0 ? 1.0 : maxYValue * 1.15;
    final yInterval = _niceAxisInterval(rawMaxY, targetTicks: 4);
    final chartMaxY = _roundUpToInterval(rawMaxY, yInterval);
    final labelInterval = max(1, (sorted.length / 4).ceil());
    final tooltipPrimaryStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        );
    final tooltipSecondaryStyle =
        (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    final gradient = LinearGradient(
      colors: [
        theme.colorScheme.primary.withValues(alpha: 0.2),
        theme.colorScheme.primary.withValues(alpha: 0.02),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: chartMaxY,
        backgroundColor: Colors.transparent,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots
                .map((spot) {
                  final index = spot.x.round();
                  if (index < 0 || index >= sorted.length) {
                    return null;
                  }
                  final point = sorted[index];
                  return LineTooltipItem(
                    _formatAmount(point.value),
                    tooltipPrimaryStyle,
                    children: [
                      TextSpan(
                        text: '\n${_formatTooltipDate(point.date)}',
                        style: tooltipSecondaryStyle,
                      ),
                    ],
                  );
                })
                .whereType<LineTooltipItem>()
                .toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: labelInterval.toDouble(),
              getTitlesWidget: (value, meta) =>
                  _buildBottomTitle(value, meta, sorted, theme, labelInterval),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: yInterval,
              getTitlesWidget: (value, meta) =>
                  _buildLeftTitle(value, meta, theme),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: chartPoints,
            isCurved: _mode != _BudgetChartMode.cumulative,
            color: theme.colorScheme.primary,
            barWidth: 3,
            belowBarData: BarAreaData(show: true, gradient: gradient),
            dotData: FlDotData(show: sorted.length <= 30),
          ),
        ],
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  /// Oblicza i wyświetla podsumowania liczbowe dla wybranego zakresu.
  Widget _buildStatistics(
    ThemeData theme,
    String currency,
    _BudgetSeries series,
    DateTimeRange range,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wydatki w wybranym zakresie: ${_formatAmount(series.rangeTotal)} $currency',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Zakres: ${_formatRangeLabel(range)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Wybiera i sortuje transakcje powiązane z tym budżetem.
  List<TransactionItem> _filterBudgetTransactions(
    List<TransactionItem> allTransactions,
  ) {
    final relevant =
        allTransactions
            .where(
              (txn) =>
                  txn.budgetId == widget.budget.id &&
                  txn.type == TransactionType.expense,
            )
            .toList()
          ..sort((a, b) => a.occurredOn.compareTo(b.occurredOn));
    return relevant;
  }

  /// Buduje serię danych do wykresu, agregując kwoty według wybranego interwału.
  _BudgetSeries _buildSeries(List<TransactionItem> allTransactions) {
    final relevant = _filterBudgetTransactions(allTransactions);
    final effectiveRange = _clampRangeToToday(_range);

    final initialSum = 0.0;

    final buckets = <DateTime, double>{};
    for (final txn in relevant) {
      if (txn.occurredOn.isBefore(effectiveRange.start) ||
          txn.occurredOn.isAfter(effectiveRange.end)) {
        continue;
      }
      final key = _bucketStart(txn.occurredOn, _interval);
      final value = txn.displayAmount ?? txn.amount;
      buckets[key] = (buckets[key] ?? 0) + value;
    }

    final timeline = _buildTimeline(effectiveRange, _interval);
    if (timeline.isEmpty) {
      timeline.add(_bucketStart(effectiveRange.start, _interval));
    }

    final points = <_ChartPoint>[];
    var running = initialSum;
    var rangeTotal = 0.0;
    var finalValue = initialSum;
    var periodsCount = 0;

    for (var index = 0; index < timeline.length; index++) {
      final date = timeline[index];
      final bucketValue = max(0.0, buckets[date] ?? 0.0);
      if (!date.isAfter(effectiveRange.end)) {
        periodsCount++;
      }
      rangeTotal += bucketValue;
      if (_mode == _BudgetChartMode.cumulative) {
        running += bucketValue;
      }
      final currentValue = _mode == _BudgetChartMode.cumulative
          ? running
          : bucketValue;
      finalValue = currentValue;
      points.add(_ChartPoint(index.toDouble(), currentValue, date));
    }

    return _BudgetSeries(
      points: points,
      rangeTotal: rangeTotal,
      finalValue: finalValue,
      periodsCount: periodsCount,
    );
  }

  /// Tworzy oś czasu na podstawie zakresu
  List<DateTime> _buildTimeline(
    DateTimeRange range,
    _BudgetChartInterval interval,
  ) {
    final dates = <DateTime>[];
    var cursor = _bucketStart(range.start, interval);
    final last = _bucketStart(range.end, interval);
    while (!cursor.isAfter(last)) {
      dates.add(cursor);
      cursor = _advanceInterval(cursor, interval);
    }
    return dates;
  }

  /// Przycina zakres dat tak, by nie wykraczał poza dzisiejszy dzień.
  DateTimeRange _clampRangeToToday(DateTimeRange range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final adjustedStart = range.start.isAfter(today) ? today : range.start;
    final adjustedEnd = range.end.isAfter(today) ? today : range.end;
    final normalizedEnd = adjustedEnd.isBefore(adjustedStart)
        ? adjustedStart
        : adjustedEnd;
    return DateTimeRange(start: adjustedStart, end: normalizedEnd);
  }

  /// Normalizuje datę do początku w zależności od interwału (dzień/tydzień/miesiąc).
  DateTime _bucketStart(DateTime date, _BudgetChartInterval interval) {
    final dayStart = DateTime(date.year, date.month, date.day);
    switch (interval) {
      case _BudgetChartInterval.daily:
        return dayStart;
      case _BudgetChartInterval.weekly:
        final weekday = dayStart.weekday;
        final difference = weekday - DateTime.monday;
        return dayStart.subtract(Duration(days: difference));
      case _BudgetChartInterval.monthly:
        return DateTime(dayStart.year, dayStart.month, 1);
    }
  }

  DateTime _advanceInterval(DateTime date, _BudgetChartInterval interval) {
    switch (interval) {
      case _BudgetChartInterval.daily:
        return date.add(const Duration(days: 1));
      case _BudgetChartInterval.weekly:
        return date.add(const Duration(days: 7));
      case _BudgetChartInterval.monthly:
        return DateTime(date.year, date.month + 1, 1);
    }
  }

  /// Wyświetla selektor zakresu dat i aktualizuje filtry po wyborze.
  Future<void> _pickDateRange() async {
    final newRange = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      helpText: 'Wybierz zakres dat dla wykresu',
      saveText: 'Zapisz',
    );
    if (newRange == null) {
      return;
    }
    setState(() {
      _range = DateTimeRange(
        start: DateTime(
          newRange.start.year,
          newRange.start.month,
          newRange.start.day,
        ),
        end: DateTime(newRange.end.year, newRange.end.month, newRange.end.day),
      );
    });
  }

  Widget _buildBottomTitle(
    double value,
    TitleMeta meta,
    List<_ChartPoint> points,
    ThemeData theme,
    int labelInterval,
  ) {
    final index = value.round();
    if (index < 0 || index >= points.length) {
      return const SizedBox.shrink();
    }
    if (index % labelInterval != 0 &&
        index != points.length - 1 &&
        index != 0) {
      return const SizedBox.shrink();
    }

    final date = points[index].date;
    final label = _interval == _BudgetChartInterval.monthly
        ? DateFormat('MMM yy', 'pl_PL').format(date)
        : DateFormat('dd.MM', 'pl_PL').format(date);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }

  Widget _buildLeftTitle(double value, TitleMeta meta, ThemeData theme) {
    if (value < 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        _formatAxisValue(value),
        style: theme.textTheme.labelSmall,
        textAlign: TextAlign.end,
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  /// Zwraca tekstowy opis zakresu w formacie `dd.MM.yyyy – dd.MM.yyyy`.
  String _formatRangeLabel(DateTimeRange range) {
    final formatter = DateFormat('dd.MM.yyyy');
    return '${formatter.format(range.start)} – ${formatter.format(range.end)}';
  }

  /// Formatuje datę w tooltipie zgodnie z aktualnym interwałem osi X.
  String _formatTooltipDate(DateTime date) {
    switch (_interval) {
      case _BudgetChartInterval.daily:
        return DateFormat('EEEE, dd.MM.yyyy', 'pl_PL').format(date);
      case _BudgetChartInterval.weekly:
        final end = date.add(const Duration(days: 6));
        return '${DateFormat('dd.MM.yyyy', 'pl_PL').format(date)} - ${DateFormat('dd.MM.yyyy', 'pl_PL').format(end)}';
      case _BudgetChartInterval.monthly:
        return DateFormat('MMMM yyyy', 'pl_PL').format(date);
    }
  }

  /// Formatuje kwoty bez miejsc po przecinku.
  String _formatAmount(double value) {
    final formatter = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: '',
      decimalDigits: 0,
    );
    return formatter.format(value).trim();
  }

  String _formatAxisValue(double value) {
    final formatter = NumberFormat.decimalPattern('pl_PL');
    return formatter.format(value.round());
  }

  double _niceAxisInterval(double maxValue, {int targetTicks = 4}) {
    if (maxValue <= 0) {
      return 1;
    }
    final rough = maxValue / targetTicks;
    final exponent = (log(rough) / ln10).floor();
    final base = pow(10, exponent).toDouble();
    final fraction = rough / base;
    double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
    return niceFraction * base;
  }

  double _roundUpToInterval(double value, double interval) {
    if (interval == 0) {
      return value;
    }
    return (value / interval).ceil() * interval;
  }

  /// Sygnalizuje, czy użytkownik zmienił zakres względem wartości domyślnej.
  bool get _isCustomRange =>
      _range.start != _defaultRange.start || _range.end != _defaultRange.end;
}

class _ChartPoint {
  _ChartPoint(this.x, this.value, this.date);

  final double x;
  final double value;
  final DateTime date;
}

class _BudgetSeries {
  _BudgetSeries({
    required this.points,
    required this.rangeTotal,
    required this.finalValue,
    required this.periodsCount,
  });

  final List<_ChartPoint> points;
  final double rangeTotal;
  final double finalValue;
  final int periodsCount;
}
