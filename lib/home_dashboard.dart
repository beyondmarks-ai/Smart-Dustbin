import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'aws_waste_repository.dart';

import 'dashboard_data.dart';
import 'report_exporter.dart';
import 'app_preferences.dart';
import 'feature_pages.dart';
import 'detection_location.dart';

abstract final class AppColors {
  static bool dark = false;
  static Color get background => dark ? Color(0xFF101C16) : Color(0xFFF7F5EE);
  static Color get card => dark ? Color(0xFF1A2921) : Color(0xFFFFFEF9);
  static Color get cardDeep => dark ? Color(0xFF22352A) : Color(0xFFF1EFE7);
  static Color get cardBorder => dark ? Color(0xFF3C5042) : Color(0xFFDEDDD3);
  static const green = Color(0xFF2C9851);
  static Color get lime => dark ? Color(0xFF78D69A) : Color(0xFF247D43);
  static Color get muted => dark ? Color(0xFFADBFB2) : Color(0xFF6F7973);
  static Color get textPrimary => dark ? Color(0xFFEDF4EF) : Color(0xFF1D2B24);
  static Color get divider => dark ? Color(0xFF34483B) : Color(0xFFE8E5DB);
}

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key, this.repository, this.onLogout});

  final VoidCallback? onLogout;

  final WasteRepository? repository;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  static const _refreshInterval = Duration(seconds: 10);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _clearedEntryKeys = <String>{};
  Timer? _refreshTimer;
  late WasteRepository _repository;
  List<WasteEntry>? _entries;
  Object? _loadError;
  bool _loadInProgress = false;
  int _loadVersion = 0;
  int _selectedNavigationIndex = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AwsWasteRepository();
    appPreferences.addListener(_preferencesChanged);
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
      _loadVersion++;
      _loadInProgress = false;
      _repository = widget.repository ?? AwsWasteRepository();
      _clearedEntryKeys.clear();
      _entries = null;
      _loadWaste();
    }
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appPreferences.removeListener(_preferencesChanged);
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadWaste({bool scrollToNewWaste = false}) async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    final requestVersion = ++_loadVersion;
    final previousTotal = _totalItems;
    try {
      final fetchedEntries = await _repository.fetchWaste();
      final visibleEntries = fetchedEntries
          .where((entry) => !_clearedEntryKeys.contains(_entryKey(entry)))
          .toList(growable: false);
      if (!mounted || requestVersion != _loadVersion) return;

      final nextTotal = _countItems(visibleEntries);
      setState(() {
        _entries = visibleEntries;
        _loadError = null;
      });
      if (scrollToNewWaste && nextTotal > previousTotal) {
        _scrollToLatestWaste();
      }
    } catch (error) {
      if (!mounted || requestVersion != _loadVersion) return;
      setState(() => _loadError = error);
    } finally {
      if (requestVersion == _loadVersion) _loadInProgress = false;
    }
  }

  Future<void> _confirmClearWaste() async {
    if ((_entries ?? <WasteEntry>[]).isEmpty) return;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: AppColors.cardDeep,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
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
                  color: Color(0xFFFF4D4D).withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_sweep_outlined,
                  color: Color(0xFFFF6868),
                  size: 27,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Clear all waste?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'This removes every waste record currently shown on your dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(46),
                        side: BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(46),
                        backgroundColor: Color(0xFFE5484D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text('Clear all'),
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
      _entries = <WasteEntry>[];
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Waste records cleared')));
  }

  void _scrollToLatestWaste() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  int get _totalItems => _countItems(_entries ?? <WasteEntry>[]);

  double get _fillLevel {
    final reset = appPreferences.emptiedAt;
    final entries = (_entries ?? <WasteEntry>[]).where((entry) {
      if (reset == null) return true;
      final captured = DateTime.tryParse(entry.capturedAt ?? '');
      return captured != null && captured.isAfter(reset);
    }).toList();
    return (_countItems(entries) / appPreferences.capacity).clamp(0.0, 1.0);
  }

  Future<void> _emptyBin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Has the bin been emptied?'),
        content: Text(
          'Reset the estimated fill level to zero. All detection history and reports will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Reset fill level'),
          ),
        ],
      ),
    );
    if (confirmed == true) await appPreferences.emptyBin();
  }

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

  Future<void> _openShareReport() async {
    final period = await showModalBottomSheet<_ReportPeriod>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShareReportSheet(),
    );
    if (period == null || !mounted) return;
    final entries = _entries ?? <WasteEntry>[];
    try {
      await WasteReportExporter.createAndShare(
        entries: _filterReportEntries(entries, period),
        periodLabel: period.label,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create the waste report.')),
        );
      }
    }
  }

  List<WasteEntry> _filterReportEntries(
    List<WasteEntry> entries,
    _ReportPeriod period,
  ) {
    if (period == _ReportPeriod.all) return entries;
    final start = DateTime.now().subtract(Duration(days: period.days));
    return entries.where((entry) {
      final captured = DateTime.tryParse(entry.capturedAt ?? '');
      return captured == null || captured.isAfter(start);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _DashboardDrawer(
        selectedIndex: _selectedNavigationIndex,
        onLogout: () {
          Navigator.pop(context);
          widget.onLogout?.call();
        },
        onSelected: (index) {
          Navigator.pop(context);
          _selectDestination(index);
        },
      ),
      bottomNavigationBar: _DashboardNavigation(
        selectedIndex: _selectedNavigationIndex,
        onSelected: _selectDestination,
      ),
      body: AnimatedSwitcher(
        duration: Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (_selectedNavigationIndex) {
          0 => _HomeView(
            key: ValueKey('home_destination'),
            scrollController: _scrollController,
            fillLevel: _fillLevel,
            entries: _entries,
            loadError: _loadError,
            onRetry: _loadWaste,
            onClear: _confirmClearWaste,
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            onShare: _openShareReport,
          ),
          1 => _InsightsView(
            key: ValueKey('insights_destination'),
            entries: _entries ?? <WasteEntry>[],
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          2 => _HistoryView(
            key: ValueKey('history_destination'),
            entries: _entries,
            loadError: _loadError,
            onRetry: _loadWaste,
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          _ => SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Open navigation',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: Icon(Icons.menu_rounded),
                    ),
                    Text(
                      'EcoSort AI',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: switch (_selectedNavigationIndex) {
                    3 => LocationPage(entries: _entries ?? []),
                    4 => FeedbackPage(),
                    _ => SettingsPage(
                      cloudOnline: _loadError == null && _entries != null,
                      checking: _loadError == null && _entries == null,
                      onRefresh: _loadWaste,
                      onEmpty: _emptyBin,
                    ),
                  },
                ),
              ],
            ),
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
    required this.onMenu,
    required this.onShare,
  });

  final ScrollController scrollController;
  final double fillLevel;
  final List<WasteEntry>? entries;
  final Object? loadError;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClear;
  final VoidCallback onMenu;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth < 370 ? 10.0 : 12.0;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                key: Key('dashboard_scroll_view'),
                controller: scrollController,
                physics: ClampingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 4, side, 18),
                    sliver: SliverList.list(
                      children: [
                        _TopBar(onMenu: onMenu, onShare: onShare),
                        SizedBox(height: 8),
                        _Greeting(),
                        SizedBox(height: 16),
                        _DeviceCard(fillLevel: fillLevel),
                        SizedBox(height: 16),
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
  const _InsightsView({super.key, required this.entries, required this.onMenu});

  final List<WasteEntry> entries;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 430),
          child: CustomScrollView(
            key: Key('insights_scroll_view'),
            physics: ClampingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 15, 12, 24),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        _HeaderButton(
                          key: Key('insights_menu_button'),
                          icon: Icons.menu_rounded,
                          label: 'Open navigation',
                          onTap: onMenu,
                        ),
                        SizedBox(width: 8),
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
                    SizedBox(height: 20),
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
  const _TopBar({required this.onMenu, required this.onShare});

  final VoidCallback onMenu;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          _HeaderButton(
            key: Key('menu_button'),
            icon: Icons.menu_rounded,
            label: 'Open navigation',
            onTap: onMenu,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'EcoSort AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 118,
            child: FilledButton.icon(
              key: Key('share_report_button'),
              onPressed: onShare,
              icon: Icon(Icons.ios_share_rounded, size: 16),
              label: Text('Share'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size(0, 38),
                textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(21),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
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
    return Column(
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
        ? Color(0xFFFF4D4D)
        : fillLevel >= .7
        ? Color(0xFFFFB020)
        : AppColors.green;

    return Container(
      key: Key('device_card'),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 15),
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
                child: Icon(
                  Icons.sensors_rounded,
                  color: AppColors.green,
                  size: 22,
                ),
              ),
              SizedBox(width: 11),
              Expanded(
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
                      'Estimated fill level',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  key: Key('fill_level_status'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: levelColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
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
                key: Key('fill_level_percentage'),
                style: TextStyle(
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ],
          ),
          SizedBox(height: 11),
          _ProgressBar(value: fillLevel, color: levelColor),
          SizedBox(height: 8),
          Row(
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
      decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
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
          key: Key('fill_level_progress'),
          value: value,
          backgroundColor: Color(0xFFE7EAE4),
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
    (label: 'Organic', count: organic, color: Color(0xFFE6A43B)),
    (label: 'Non-recyclable', count: nonRecyclable, color: Color(0xFFFF5D62)),
    (label: 'Other', count: other, color: Color(0xFF718996)),
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
          key: Key('waste_statistics_card'),
          padding: EdgeInsets.fromLTRB(15, 15, 15, 14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
              SizedBox(height: 17),
              Row(
                children: [
                  SizedBox(
                    width: 118,
                    height: 118,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          key: Key('waste_category_chart'),
                          size: Size.square(118),
                          painter: _DonutChartPainter(metrics.categories),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${metrics.total}',
                              key: Key('waste_total_items_chart'),
                              style: TextStyle(
                                fontSize: 23,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
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
                  SizedBox(width: 17),
                  Expanded(
                    child: Column(
                      children: [
                        for (final category in metrics.categories)
                          Padding(
                            padding: EdgeInsets.only(bottom: 9),
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
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category.label,
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                Text(
                                  '${category.count}',
                                  key: Key(
                                    'category_${category.label.toLowerCase()}',
                                  ),
                                  style: TextStyle(
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
              SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  key: Key('waste_composition_chart'),
                  height: 9,
                  child: metrics.total == 0
                      ? ColoredBox(color: Color(0xFFE7EAE4))
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
        SizedBox(height: 12),
        _EnvironmentalImpactCard(metrics: metrics),
        SizedBox(height: 12),
        _WasteTrendCard(entries: entries),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter(this.categories);

  final List<({String label, int count, Color color})> categories;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = categories.fold<int>(0, (sum, item) => sum + item.count);
    final track = Paint()
      ..color = Color(0xFFE7EAE4)
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
      key: Key('environmental_impact_card'),
      padding: EdgeInsets.fromLTRB(15, 15, 15, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Color(0xFFCBE2D0), width: .8),
        gradient: LinearGradient(
          colors: AppColors.dark
              ? [AppColors.card, AppColors.cardDeep]
              : [Color(0xFFEAF5EB), Color(0xFFF7F7F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          SizedBox(height: 16),
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
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 11),
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
            SizedBox(height: 7),
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
            SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(color: AppColors.muted, fontSize: 9),
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
      key: Key('date_wise_waste_chart_card'),
      padding: EdgeInsets.fromLTRB(15, 15, 15, 13),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          SizedBox(height: 14),
          Row(
            children: [
              _TrendLegend(
                color: AppColors.green,
                label: 'Recyclable',
                total: recyclableTotal,
              ),
              SizedBox(width: 16),
              _TrendLegend(
                color: Color(0xFFFF5D62),
                label: 'Non-recyclable',
                total: nonRecyclableTotal,
              ),
            ],
          ),
          SizedBox(height: 12),
          if (points.isEmpty)
            SizedBox(
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
                key: Key('date_wise_waste_chart'),
                height: 220,
                width: double.infinity,
                child: CustomPaint(painter: _WasteTrendPainter(points)),
              ),
            ),
          SizedBox(height: 3),
          Center(
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
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10),
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
  _WasteTrendPainter(this.points);

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
      ..color = Color(0xFFE0E3DD)
      ..strokeWidth = 1;

    for (var index = 0; index <= 4; index++) {
      final y = plot.bottom - (plot.height * index / 4);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawLabel(
        canvas,
        '${(yMax * index / 4).round()}',
        Offset(0, y - 6),
        Size(27, 14),
        TextAlign.right,
      );
    }

    final axisPaint = Paint()
      ..color = Color(0xFFAAB5AE)
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
      Color(0xFFFF5D62),
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
      Size(30, 12),
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
      return _WasteInventoryShell(
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
          SizedBox(height: 16),
          Text(
            'Unable to load waste detections',
            style: TextStyle(color: AppColors.muted),
          ),
          SizedBox(height: 4),
          TextButton(onPressed: onRetry, child: Text('Retry')),
          SizedBox(height: 8),
        ],
      );
    }
    if (wasteEntries!.isEmpty) {
      return _WasteInventoryShell(
        total: '0',
        children: [
          SizedBox(
            height: 96,
            child: Center(child: Text('No waste detected yet')),
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
            Padding(
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
      key: Key('waste_inventory_card'),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 5, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Waste Inside Dustbin',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: Key('clear_all_waste_button'),
                  tooltip: 'Clear all waste',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  iconSize: 19,
                  icon: Icon(Icons.delete_sweep_outlined),
                ),
                _StatusDot(),
                SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          ...children,
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 16, 13),
            child: Row(
              children: [
                Expanded(
                  child: Text('Total Items', style: TextStyle(fontSize: 12)),
                ),
                Text(
                  total,
                  key: Key('waste_inventory_total'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
      onTap: () => _showWasteDetails(context, entry),
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.cardDeep,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: Color(0xFFDDE1DA), width: .7),
                ),
                clipBehavior: Clip.antiAlias,
                child: entry.imageUrl != null
                    ? Image.network(
                        entry.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Icon(
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
                    : Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.muted,
                      ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 5),
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
              SizedBox(width: 12),
              SizedBox(
                width: 24,
                child: Text(
                  entry.count.toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DetectionDetailsPage(entry: entry)),
  );
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({
    super.key,
    required this.entries,
    required this.loadError,
    required this.onRetry,
    required this.onMenu,
  });

  final List<WasteEntry>? entries;
  final Object? loadError;
  final Future<void> Function() onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final wasteEntries = entries;
    final total =
        wasteEntries?.fold<int>(0, (sum, entry) => sum + entry.count) ?? 0;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 430),
          child: CustomScrollView(
            key: Key('history_scroll_view'),
            physics: ClampingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        _HeaderButton(
                          key: Key('history_menu_button'),
                          icon: Icons.menu_rounded,
                          label: 'Open navigation',
                          onTap: onMenu,
                        ),
                        SizedBox(width: 8),
                        Expanded(
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
                                'Your latest detections and review items',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          key: Key('history_refresh_button'),
                          tooltip: 'Refresh history',
                          onPressed: onRetry,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.green,
                          ),
                          icon: Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    SizedBox(height: 22),
                    Container(
                      key: Key('history_summary_card'),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: AppColors.dark
                              ? [AppColors.card, AppColors.cardDeep]
                              : [Color(0xFFE5F3E8), Color(0xFFF7F7F0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: Color(0xFFC5DFC9)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: Color(0x2231C34B),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.history_rounded,
                              color: AppColors.lime,
                            ),
                          ),
                          SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${wasteEntries?.length ?? 0} records',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  '$total total items detected',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StatusDot(),
                          SizedBox(width: 6),
                          Text(
                            loadError != null
                                ? 'Offline'
                                : wasteEntries == null
                                ? 'Syncing'
                                : 'Live',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    if (wasteEntries == null && loadError == null)
                      SizedBox(
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
                          child: Text('Retry'),
                        ),
                      )
                    else if (wasteEntries!.isEmpty)
                      _HistoryMessage(
                        icon: Icons.history_toggle_off_rounded,
                        title: 'No history yet',
                        message: 'Camera detections will appear here.',
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
                          SizedBox(height: 10),
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
        side: BorderSide(color: AppColors.cardBorder, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showWasteDetails(context, entry),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.cardDeep,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: entry.imageUrl != null
                    ? Image.network(
                        entry.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.muted,
                        ),
                      )
                    : entry.asset != null
                    ? Image.asset(entry.asset!, fit: BoxFit.cover)
                    : Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.muted,
                      ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
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
                    SizedBox(height: 9),
                    Text(
                      entry.locationLabel.isEmpty
                          ? 'Location not recorded'
                          : entry.locationLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      detectedTime(entry.capturedAt),
                      style: TextStyle(fontSize: 10, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.confidence}%',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 7),
                  Icon(
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
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: _cardDecoration(),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: AppColors.muted, size: 34),
            SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (action != null) ...[SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

enum _ReportPeriod {
  today('Today', 1),
  lastSevenDays('Last 7 days', 7),
  lastThirtyDays('Last 30 days', 30),
  all('All records', 0);

  const _ReportPeriod(this.label, this.days);
  final String label;
  final int days;
}

class _ShareReportSheet extends StatefulWidget {
  const _ShareReportSheet();

  @override
  State<_ShareReportSheet> createState() => _ShareReportSheetState();
}

class _ShareReportSheetState extends State<_ShareReportSheet> {
  _ReportPeriod _selected = _ReportPeriod.lastSevenDays;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(22, 12, 22, 28),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(height: 22),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0x1A2C9851),
                child: Icon(Icons.table_view_rounded, color: AppColors.green),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share waste report',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Excel file (.xlsx) with summary and detections',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          Text(
            'Period',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 9,
            children: [
              for (final period in _ReportPeriod.values)
                ChoiceChip(
                  label: Text(period.label),
                  selected: _selected == period,
                  onSelected: (_) => setState(() => _selected = period),
                  selectedColor: AppColors.green.withValues(alpha: .14),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _selected == period
                        ? AppColors.lime
                        : AppColors.textPrimary,
                  ),
                ),
            ],
          ),
          SizedBox(height: 26),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _selected),
            icon: Icon(Icons.ios_share_rounded),
            label: Text(
              'Create and share',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(27),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DashboardDrawer extends StatelessWidget {
  const _DashboardDrawer({
    required this.selectedIndex,
    required this.onSelected,
    required this.onLogout,
  });
  final VoidCallback onLogout;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: Color(0xFF0E4F34),
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: ListView(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.green,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 11),
                Text(
                  'EcoSort AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 36),
            _DrawerDestination(
              icon: Icons.grid_view_rounded,
              label: 'Dashboard',
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _DrawerDestination(
              icon: Icons.insights_outlined,
              label: 'Analytics',
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _DrawerDestination(
              icon: Icons.history_rounded,
              label: 'Detections',
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
            _DrawerDestination(
              icon: Icons.location_on_outlined,
              label: 'Location',
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
            _DrawerDestination(
              icon: Icons.rate_review_outlined,
              label: 'Sentiment analysis',
              selected: selectedIndex == 4,
              onTap: () => onSelected(4),
            ),
            _DrawerDestination(
              icon: Icons.settings_outlined,
              label: 'Settings',
              selected: selectedIndex == 5,
              onTap: () => onSelected(5),
            ),
            _DrawerDestination(
              icon: Icons.logout,
              label: 'Logout',
              onTap: onLogout,
            ),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: AppColors.green,
                    child: Text(
                      'AD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EcoSort user',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Single-camera workspace',
                          style: TextStyle(
                            color: Color(0xFFC0D8CA),
                            fontSize: 10,
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
      ),
    ),
  );
}

class _DrawerDestination extends StatelessWidget {
  const _DrawerDestination({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 21),
              SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
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
      key: Key('bottom_navigation'),
      decoration: BoxDecoration(
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
            padding: EdgeInsets.only(top: 9, bottom: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 23, color: color),
                SizedBox(height: 4),
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
    boxShadow: [
      BoxShadow(color: Color(0x160F2D1C), blurRadius: 18, offset: Offset(0, 6)),
    ],
  );
}
