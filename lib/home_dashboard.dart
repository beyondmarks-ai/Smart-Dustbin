import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'aws_waste_repository.dart';

import 'dashboard_data.dart';

abstract final class AppColors {
  static const background = Color(0xFFF7F5EE);
  static const card = Color(0xFFFFFEF9);
  static const cardDeep = Color(0xFFF1EFE7);
  static const cardBorder = Color(0xFFDEDDD3);
  static const green = Color(0xFF2C9851);
  static const lime = Color(0xFF247D43);
  static const muted = Color(0xFF6F7973);
  static const textPrimary = Color(0xFF1D2B24);
  static const divider = Color(0xFFE8E5DB);
}

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key, this.repository});

  final WasteRepository? repository;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  static const _refreshInterval = Duration(seconds: 10);
  static const _binCapacity = 50;

  final ScrollController _scrollController = ScrollController();
  final Set<String> _clearedEntryKeys = <String>{};
  Timer? _refreshTimer;
  late WasteRepository _repository;
  List<WasteEntry>? _entries;
  Object? _loadError;
  int _selectedNavigationIndex = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AwsWasteRepository();
    _loadWaste();
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _loadWaste(scrollToNewWaste: true),
    );
  }

  @override
  void didUpdateWidget(covariant HomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _repository = widget.repository ?? AwsWasteRepository();
      _clearedEntryKeys.clear();
      _entries = null;
      _loadWaste();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadWaste({bool scrollToNewWaste = false}) async {
    final previousTotal = _totalItems;
    try {
      final fetchedEntries = await _repository.fetchWaste();
      final visibleEntries = fetchedEntries
          .where((entry) => !_clearedEntryKeys.contains(_entryKey(entry)))
          .toList(growable: false);
      if (!mounted) return;

      final nextTotal = _countItems(visibleEntries);
      setState(() {
        _entries = visibleEntries;
        _loadError = null;
      });
      if (scrollToNewWaste && nextTotal > previousTotal) {
        _scrollToLatestWaste();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _confirmClearWaste() async {
    if ((_entries ?? const <WasteEntry>[]).isEmpty) return;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: AppColors.cardDeep,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D4D).withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Color(0xFFFF6868),
                  size: 27,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Clear all waste?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'This removes every waste record currently shown on your dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: const Color(0xFFE5484D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text('Clear all'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldClear != true || !mounted) return;

    setState(() {
      _clearedEntryKeys.addAll(_entries!.map(_entryKey));
      _entries = const <WasteEntry>[];
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Waste records cleared')));
  }

  void _scrollToLatestWaste() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  int get _totalItems => _countItems(_entries ?? const <WasteEntry>[]);

  double get _fillLevel => (_totalItems / _binCapacity).clamp(0.0, 1.0);

  static int _countItems(List<WasteEntry> entries) =>
      entries.fold<int>(0, (sum, entry) => sum + entry.count);

  static String _entryKey(WasteEntry entry) {
    final eventId = entry.eventId;
    if (eventId != null && eventId.isNotEmpty) {
      return '$eventId:${entry.itemIndex}';
    }
    return '${entry.name}|${entry.classification}|${entry.count}|'
        '${entry.asset}|${entry.imageUrl}';
  }

  void _selectDestination(int index) {
    if (_selectedNavigationIndex == index) return;
    setState(() => _selectedNavigationIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _DashboardNavigation(
        selectedIndex: _selectedNavigationIndex,
        onSelected: _selectDestination,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (_selectedNavigationIndex) {
          0 => _HomeView(
            key: const ValueKey('home_destination'),
            scrollController: _scrollController,
            fillLevel: _fillLevel,
            entries: _entries,
            loadError: _loadError,
            onRetry: _loadWaste,
            onClear: _confirmClearWaste,
          ),
          1 => _InsightsView(
            key: const ValueKey('insights_destination'),
            entries: _entries ?? const <WasteEntry>[],
          ),
          _ => _HistoryView(
            key: const ValueKey('history_destination'),
            entries: _entries,
            loadError: _loadError,
            onRetry: _loadWaste,
          ),
        },
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    super.key,
    required this.scrollController,
    required this.fillLevel,
    required this.entries,
    required this.loadError,
    required this.onRetry,
    required this.onClear,
  });

  final ScrollController scrollController;
  final double fillLevel;
  final List<WasteEntry>? entries;
  final Object? loadError;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth < 370 ? 10.0 : 12.0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                key: const Key('dashboard_scroll_view'),
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 4, side, 18),
                    sliver: SliverList.list(
                      children: [
                        const _TopBar(),
                        const SizedBox(height: 8),
                        const _Greeting(),
                        const SizedBox(height: 16),
                        _DeviceCard(fillLevel: fillLevel),
                        const SizedBox(height: 16),
                        _WasteInventoryCard(
                          entries: entries,
                          loadError: loadError,
                          onRetry: onRetry,
                          onClear: onClear,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InsightsView extends StatelessWidget {
  const _InsightsView({super.key, required this.entries});

  final List<WasteEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: CustomScrollView(
            key: const Key('insights_scroll_view'),
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 15, 12, 24),
                sliver: SliverList.list(
                  children: [
                    const Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Insights',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.4,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Waste performance and environmental impact',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.insights_rounded,
                          color: AppColors.green,
                          size: 27,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _WasteAnalyticsSection(entries: entries),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 38,
      child: Align(
        alignment: Alignment.centerRight,
        child: _HeaderButton(
          key: Key('notification_button'),
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: () {},
          radius: 22,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 24, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hello, User 👋',
          style: TextStyle(
            fontSize: 20,
            height: 1.15,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.35,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Here’s your smart dustbin overview',
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.2),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.fillLevel});

  final double fillLevel;

  @override
  Widget build(BuildContext context) {
    final percentage = (fillLevel * 100).round();
    final status = switch (fillLevel) {
      0 => 'Empty',
      >= .9 => 'Full',
      >= .7 => 'Almost full',
      _ => 'Normal',
    };
    final levelColor = fillLevel >= .9
        ? const Color(0xFFFF4D4D)
        : fillLevel >= .7
        ? const Color(0xFFFFB020)
        : AppColors.green;

    return Container(
      key: const Key('device_card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.sensors_rounded,
                  color: AppColors.green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart Bin',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Live capacity monitor',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  key: const Key('fill_level_status'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: levelColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  'Fill Level',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$percentage%',
                key: const Key('fill_level_percentage'),
                style: const TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          _ProgressBar(value: fillLevel, color: levelColor),
          const SizedBox(height: 8),
          const Row(
            children: [
              Text('0%', style: TextStyle(color: AppColors.muted, fontSize: 9)),
              Spacer(),
              Text(
                'Capacity: 50 items',
                style: TextStyle(color: AppColors.muted, fontSize: 9),
              ),
              Spacer(),
              Text(
                '100%',
                style: TextStyle(color: AppColors.muted, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppColors.green,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 8,
        child: LinearProgressIndicator(
          key: const Key('fill_level_progress'),
          value: value,
          backgroundColor: const Color(0xFFE7EAE4),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

class _WasteMetrics {
  const _WasteMetrics({
    required this.total,
    required this.recyclable,
    required this.organic,
    required this.nonRecyclable,
    required this.other,
  });

  factory _WasteMetrics.fromEntries(List<WasteEntry> entries) {
    var recyclable = 0;
    var organic = 0;
    var nonRecyclable = 0;
    var other = 0;

    for (final entry in entries) {
      final description =
          '${entry.category} ${entry.classification} '
                  '${entry.material}'
              .toLowerCase();
      if (description.contains('non-recyclable') ||
          description.contains('non recyclable')) {
        nonRecyclable += entry.count;
      } else if (description.contains('organic') ||
          description.contains('food')) {
        organic += entry.count;
      } else if (entry.recyclable || description.contains('recyclable')) {
        recyclable += entry.count;
      } else {
        other += entry.count;
      }
    }

    return _WasteMetrics(
      total: recyclable + organic + nonRecyclable + other,
      recyclable: recyclable,
      organic: organic,
      nonRecyclable: nonRecyclable,
      other: other,
    );
  }

  final int total;
  final int recyclable;
  final int organic;
  final int nonRecyclable;
  final int other;

  double get recyclingRate => total == 0 ? 0 : recyclable / total;

  List<({String label, int count, Color color})> get categories => [
    (label: 'Recyclable', count: recyclable, color: AppColors.green),
    (label: 'Organic', count: organic, color: const Color(0xFFE6A43B)),
    (
      label: 'Non-recyclable',
      count: nonRecyclable,
      color: const Color(0xFFFF5D62),
    ),
    (label: 'Other', count: other, color: const Color(0xFF718996)),
  ];
}

class _WasteAnalyticsSection extends StatelessWidget {
  const _WasteAnalyticsSection({required this.entries});

  final List<WasteEntry> entries;

  @override
  Widget build(BuildContext context) {
    final metrics = _WasteMetrics.fromEntries(entries);
    return Column(
      children: [
        Container(
          key: const Key('waste_statistics_card'),
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Waste Statistics',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Live category distribution',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.bar_chart_rounded,
                    color: AppColors.green,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  SizedBox(
                    width: 118,
                    height: 118,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          key: const Key('waste_category_chart'),
                          size: const Size.square(118),
                          painter: _DonutChartPainter(metrics.categories),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${metrics.total}',
                              key: const Key('waste_total_items_chart'),
                              style: const TextStyle(
                                fontSize: 23,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'items',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 17),
                  Expanded(
                    child: Column(
                      children: [
                        for (final category in metrics.categories)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: category.color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category.label,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Text(
                                  '${category.count}',
                                  key: Key(
                                    'category_${category.label.toLowerCase()}',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  key: const Key('waste_composition_chart'),
                  height: 9,
                  child: metrics.total == 0
                      ? const ColoredBox(color: Color(0xFFE7EAE4))
                      : Row(
                          children: [
                            for (final category in metrics.categories)
                              if (category.count > 0)
                                Expanded(
                                  flex: category.count,
                                  child: ColoredBox(color: category.color),
                                ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _EnvironmentalImpactCard(metrics: metrics),
        const SizedBox(height: 12),
        _WasteTrendCard(entries: entries),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter(this.categories);

  final List<({String label, int count, Color color})> categories;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = categories.fold<int>(0, (sum, item) => sum + item.count);
    final track = Paint()
      ..color = const Color(0xFFE7EAE4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawCircle(center, radius, track);
    if (total == 0) return;

    var start = -math.pi / 2;
    for (final category in categories) {
      if (category.count == 0) continue;
      final sweep = (category.count / total) * math.pi * 2;
      final paint = Paint()
        ..color = category.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = 14;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.categories != categories;
}

class _EnvironmentalImpactCard extends StatelessWidget {
  const _EnvironmentalImpactCard({required this.metrics});

  final _WasteMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final co2Saved = metrics.recyclable * .08;
    final diverted = metrics.recyclable * .035;
    return Container(
      key: const Key('environmental_impact_card'),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFCBE2D0), width: .8),
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF5EB), Color(0xFFF7F7F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.eco_outlined, color: AppColors.lime, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Environmental Impact',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'ESTIMATED',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ImpactMetric(
                icon: Icons.cloud_outlined,
                color: Color(0xFF347FC4),
                background: Color(0xFFEAF4FD),
                border: Color(0xFFCDE2F5),
                value: '${co2Saved.toStringAsFixed(1)} kg',
                label: 'CO₂ saved',
              ),
              SizedBox(width: 8),
              _ImpactMetric(
                icon: Icons.recycling_rounded,
                color: AppColors.green,
                background: Color(0xFFE9F5EC),
                border: Color(0xFFC9E3CF),
                value: '${(metrics.recyclingRate * 100).round()}%',
                label: 'Recycling rate',
              ),
              SizedBox(width: 8),
              _ImpactMetric(
                icon: Icons.delete_outline_rounded,
                color: Color(0xFFC67A18),
                background: Color(0xFFFDF2E2),
                border: Color(0xFFF0D8B2),
                value: '${diverted.toStringAsFixed(1)} kg',
                label: 'Waste diverted',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImpactMetric extends StatelessWidget {
  const _ImpactMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(color: AppColors.muted, fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyWasteCount {
  _DailyWasteCount({required this.date, required this.label});

  final DateTime? date;
  final String label;
  int recyclable = 0;
  int nonRecyclable = 0;
}

class _WasteTrendCard extends StatelessWidget {
  const _WasteTrendCard({required this.entries});

  final List<WasteEntry> entries;

  static const _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  List<_DailyWasteCount> _dailyCounts() {
    final grouped = <String, _DailyWasteCount>{};
    for (final entry in entries) {
      final parsed = DateTime.tryParse(entry.capturedAt ?? '')?.toLocal();
      final date = parsed == null
          ? null
          : DateTime(parsed.year, parsed.month, parsed.day);
      final key = date == null
          ? 'undated'
          : '${date.year}-${date.month}-${date.day}';
      final point = grouped.putIfAbsent(
        key,
        () => _DailyWasteCount(
          date: date,
          label: date == null
              ? 'Today'
              : '${date.day} ${_months[date.month - 1]}',
        ),
      );
      if (_isRecyclable(entry)) {
        point.recyclable += entry.count;
      } else {
        point.nonRecyclable += entry.count;
      }
    }

    final result = grouped.values.toList()
      ..sort((a, b) {
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });
    return result.length <= 7 ? result : result.sublist(result.length - 7);
  }

  static bool _isRecyclable(WasteEntry entry) {
    final description =
        '${entry.category} ${entry.classification} '
                '${entry.material}'
            .toLowerCase();
    final explicitlyNonRecyclable =
        description.contains('non-recyclable') ||
        description.contains('non recyclable') ||
        description.contains('not recyclable');
    return !explicitlyNonRecyclable &&
        (entry.recyclable || description.contains('recyclable'));
  }

  @override
  Widget build(BuildContext context) {
    final points = _dailyCounts();
    final recyclableTotal = points.fold<int>(
      0,
      (sum, point) => sum + point.recyclable,
    );
    final nonRecyclableTotal = points.fold<int>(
      0,
      (sum, point) => sum + point.nonRecyclable,
    );

    return Container(
      key: const Key('date_wise_waste_chart_card'),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 13),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waste Trend',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Recyclable vs non-recyclable by date',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.show_chart_rounded, color: AppColors.green, size: 22),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TrendLegend(
                color: AppColors.green,
                label: 'Recyclable',
                total: recyclableTotal,
              ),
              const SizedBox(width: 16),
              _TrendLegend(
                color: Color(0xFFFF5D62),
                label: 'Non-recyclable',
                total: nonRecyclableTotal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (points.isEmpty)
            const SizedBox(
              height: 190,
              child: Center(
                child: Text(
                  'Trend data will appear after the first detection',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            )
          else
            Semantics(
              label:
                  'Date-wise waste chart. Green represents recyclable waste and red represents non-recyclable waste.',
              child: SizedBox(
                key: const Key('date_wise_waste_chart'),
                height: 220,
                width: double.infinity,
                child: CustomPaint(painter: _WasteTrendPainter(points)),
              ),
            ),
          const SizedBox(height: 3),
          const Center(
            child: Text(
              'Detection date',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({
    required this.color,
    required this.label,
    required this.total,
  });

  final Color color;
  final String label;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            Text(
              '$total',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WasteTrendPainter extends CustomPainter {
  const _WasteTrendPainter(this.points);

  final List<_DailyWasteCount> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const top = 8.0;
    const right = 8.0;
    const bottom = 31.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final highest = points.fold<int>(
      0,
      (value, point) =>
          math.max(value, math.max(point.recyclable, point.nonRecyclable)),
    );
    final yMax = math.max(4, (highest / 4).ceil() * 4);
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E3DD)
      ..strokeWidth = 1;

    for (var index = 0; index <= 4; index++) {
      final y = plot.bottom - (plot.height * index / 4);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawLabel(
        canvas,
        '${(yMax * index / 4).round()}',
        Offset(0, y - 6),
        const Size(27, 14),
        TextAlign.right,
      );
    }

    final axisPaint = Paint()
      ..color = const Color(0xFFAAB5AE)
      ..strokeWidth = 1.2;
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);

    double xFor(int index) => points.length == 1
        ? plot.center.dx
        : plot.left + (plot.width * index / (points.length - 1));
    double yFor(int value) => plot.bottom - (plot.height * value / yMax);

    _drawSeries(
      canvas,
      plot,
      List<Offset>.generate(
        points.length,
        (index) => Offset(xFor(index), yFor(points[index].recyclable)),
      ),
      AppColors.green,
    );
    _drawSeries(
      canvas,
      plot,
      List<Offset>.generate(
        points.length,
        (index) => Offset(xFor(index), yFor(points[index].nonRecyclable)),
      ),
      const Color(0xFFFF5D62),
    );

    for (var index = 0; index < points.length; index++) {
      final center = xFor(index);
      final labelWidth = math.min(48.0, plot.width / points.length);
      _drawLabel(
        canvas,
        points[index].label,
        Offset(center - labelWidth / 2, plot.bottom + 9),
        Size(labelWidth, 16),
        TextAlign.center,
      );
    }

    canvas.save();
    canvas.translate(8, plot.center.dy + 14);
    canvas.rotate(-math.pi / 2);
    _drawLabel(
      canvas,
      'Items',
      Offset.zero,
      const Size(30, 12),
      TextAlign.center,
      fontSize: 8,
    );
    canvas.restore();
  }

  void _drawSeries(
    Canvas canvas,
    Rect plot,
    List<Offset> offsets,
    Color color,
  ) {
    if (offsets.isEmpty) return;
    final areaPath = Path()
      ..moveTo(offsets.first.dx, plot.bottom)
      ..lineTo(offsets.first.dx, offsets.first.dy);
    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    _addSmoothSegments(linePath, offsets);
    _addSmoothSegments(areaPath, offsets);
    areaPath
      ..lineTo(offsets.last.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .18), color.withValues(alpha: .01)],
        ).createShader(plot),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (final point in offsets) {
      canvas.drawCircle(point, 4.2, Paint()..color = AppColors.card);
      canvas.drawCircle(point, 3, Paint()..color = color);
    }
  }

  void _addSmoothSegments(Path path, List<Offset> offsets) {
    if (offsets.length < 2) return;
    for (var index = 0; index < offsets.length - 1; index++) {
      final current = offsets[index];
      final next = offsets[index + 1];
      final controlDistance = (next.dx - current.dx) * .38;
      path.cubicTo(
        current.dx + controlDistance,
        current.dy,
        next.dx - controlDistance,
        next.dy,
        next.dx,
        next.dy,
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset,
    Size size,
    TextAlign align, {
    double fontSize = 8.5,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: AppColors.muted, fontSize: fontSize),
      ),
      textAlign: align,
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _WasteTrendPainter oldDelegate) => true;
}

class _WasteInventoryCard extends StatelessWidget {
  const _WasteInventoryCard({
    required this.entries,
    required this.loadError,
    required this.onRetry,
    required this.onClear,
  });

  final List<WasteEntry>? entries;
  final Object? loadError;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final wasteEntries = entries;
    if (wasteEntries == null && loadError == null) {
      return const _WasteInventoryShell(
        total: '—',
        children: [
          SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      );
    }
    if (wasteEntries == null && loadError != null) {
      return _WasteInventoryShell(
        total: '0',
        children: [
          const SizedBox(height: 16),
          Text(
            'Unable to load verified waste',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
          const SizedBox(height: 8),
        ],
      );
    }
    if (wasteEntries!.isEmpty) {
      return const _WasteInventoryShell(
        total: '0',
        children: [
          SizedBox(
            height: 96,
            child: Center(child: Text('No verified waste detected yet')),
          ),
        ],
      );
    }
    return _WasteInventoryShell(
      total: wasteEntries
          .fold<int>(0, (sum, entry) => sum + entry.count)
          .toString(),
      onClear: onClear,
      children: [
        for (var index = 0; index < wasteEntries.length; index++) ...[
          _WasteRow(entry: wasteEntries[index]),
          if (index != wasteEntries.length - 1)
            const Padding(
              padding: EdgeInsets.only(left: 64, right: 14),
              child: Divider(height: 1, thickness: 1, color: AppColors.divider),
            ),
        ],
      ],
    );
  }
}

class _WasteInventoryShell extends StatelessWidget {
  const _WasteInventoryShell({
    required this.total,
    this.onClear,
    required this.children,
  });

  final List<Widget> children;
  final String total;
  final Future<void> Function()? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('waste_inventory_card'),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 5, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Waste Inside Dustbin',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const Key('clear_all_waste_button'),
                  tooltip: 'Clear all waste',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  iconSize: 19,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                const _StatusDot(),
                const SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          ...children,
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 16, 13),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Total Items', style: TextStyle(fontSize: 12)),
                ),
                Text(
                  total,
                  key: const Key('waste_inventory_total'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

class _WasteRow extends StatelessWidget {
  const _WasteRow({required this.entry});

  final WasteEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('waste_row_${entry.count}'),
      onTap: entry.imageUrl == null
          ? null
          : () => _showWasteDetails(context, entry),
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1EB),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFDDE1DA), width: .7),
                ),
                clipBehavior: Clip.antiAlias,
                child: entry.imageUrl != null
                    ? Image.network(
                        entry.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.muted,
                        ),
                      )
                    : entry.asset != null
                    ? Image.asset(
                        entry.asset!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      )
                    : const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.muted,
                      ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.classification,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                        color: entry.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 24,
                child: Text(
                  entry.count.toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showWasteDetails(BuildContext context, WasteEntry entry) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardDeep,
    barrierColor: Colors.black.withValues(alpha: .45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  entry.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const Center(
                    child: Icon(Icons.image_not_supported_outlined, size: 42),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              entry.name,
              style: const TextStyle(
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entry.tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.card,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            _DetailLine(label: 'Material', value: entry.material),
            _DetailLine(
              label: 'Waste confidence',
              value: '${entry.confidence}%',
            ),
            _DetailLine(
              label: 'Recycling',
              value: entry.recyclable ? 'Recyclable' : 'Not recyclable',
            ),
            if (entry.recyclingGuidance.isNotEmpty)
              _DetailLine(
                label: 'Recycling guidance',
                value: entry.recyclingGuidance,
              ),
            if (entry.contaminationNotes.isNotEmpty)
              _DetailLine(
                label: 'Contamination',
                value: entry.contaminationNotes,
              ),
            if (entry.reuseSafe && entry.reuseIdeas.isNotEmpty)
              _DetailLine(
                label: 'Best from waste',
                value: entry.reuseIdeas.join(' • '),
              ),
            if (entry.safetyWarnings.isNotEmpty)
              _DetailLine(
                label: 'Safety',
                value: entry.safetyWarnings.join(' • '),
              ),
            if (entry.evidenceSummary.isNotEmpty)
              _DetailLine(label: 'AI evidence', value: entry.evidenceSummary),
          ],
        ),
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, height: 1.25)),
        ],
      ),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({
    super.key,
    required this.entries,
    required this.loadError,
    required this.onRetry,
  });

  final List<WasteEntry>? entries;
  final Object? loadError;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final wasteEntries = entries;
    final total =
        wasteEntries?.fold<int>(0, (sum, entry) => sum + entry.count) ?? 0;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: CustomScrollView(
            key: const Key('history_scroll_view'),
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Waste History',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.4,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Your latest verified detections',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          key: const Key('history_refresh_button'),
                          tooltip: 'Refresh history',
                          onPressed: onRetry,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.green,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      key: const Key('history_summary_card'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE5F3E8), Color(0xFFF7F7F0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: const Color(0xFFC5DFC9)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 45,
                            height: 45,
                            decoration: const BoxDecoration(
                              color: Color(0x2231C34B),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              color: AppColors.lime,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${wasteEntries?.length ?? 0} records',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$total total items detected',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const _StatusDot(),
                          const SizedBox(width: 6),
                          const Text(
                            'Live',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (wasteEntries == null && loadError == null)
                      const SizedBox(
                        height: 180,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (loadError != null && wasteEntries == null)
                      _HistoryMessage(
                        icon: Icons.cloud_off_outlined,
                        title: 'History unavailable',
                        message: 'Check your connection and try again.',
                        action: TextButton(
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                      )
                    else if (wasteEntries!.isEmpty)
                      const _HistoryMessage(
                        icon: Icons.history_toggle_off_rounded,
                        title: 'No history yet',
                        message: 'Verified detections will appear here.',
                      )
                    else
                      for (
                        var index = 0;
                        index < wasteEntries.length;
                        index++
                      ) ...[
                        _HistoryEntryCard(
                          entry: wasteEntries[index],
                          index: index,
                        ),
                        if (index != wasteEntries.length - 1)
                          const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry, required this.index});

  final WasteEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key('history_entry_$index'),
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.imageUrl == null
            ? null
            : () => _showWasteDetails(context, entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1EB),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: entry.imageUrl != null
                    ? Image.network(
                        entry.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.muted,
                        ),
                      )
                    : entry.asset != null
                    ? Image.asset(entry.asset!, fit: BoxFit.cover)
                    : const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.muted,
                      ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.classification,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: entry.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '×${entry.count}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: _cardDecoration(),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: AppColors.muted, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class _DashboardNavigation extends StatelessWidget {
  const _DashboardNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const items = <({String label, IconData icon})>[
    (label: 'Home', icon: Icons.home_outlined),
    (label: 'Insights', icon: Icons.insights_outlined),
    (label: 'History', icon: Icons.history_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('bottom_navigation'),
      decoration: const BoxDecoration(
        color: AppColors.cardDeep,
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _NavigationItem(
                    item: items[index],
                    active: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final ({String label, IconData icon}) item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.lime : AppColors.muted;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('navigation_${item.label.toLowerCase()}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(top: 9, bottom: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 23, color: color),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(13),
    border: Border.all(
      color: AppColors.cardBorder.withValues(alpha: .7),
      width: .7,
    ),
    boxShadow: const [
      BoxShadow(color: Color(0x160F2D1C), blurRadius: 18, offset: Offset(0, 6)),
    ],
  );
}
