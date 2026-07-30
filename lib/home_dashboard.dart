import 'dart:async';

import 'package:flutter/material.dart';

import 'azure_waste_repository.dart';

import 'dashboard_data.dart';

abstract final class AppColors {
  static const background = Color(0xFF001019);
  static const card = Color(0xFF091C26);
  static const cardDeep = Color(0xFF071821);
  static const cardBorder = Color(0xFF102A35);
  static const green = Color(0xFF31C34B);
  static const lime = Color(0xFFA6F000);
  static const muted = Color(0xFF9EABB2);
  static const textPrimary = Color(0xFFF4F6F7);
  static const divider = Color(0xFF17303A);
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

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AzureWasteRepository();
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
      _repository = widget.repository ?? AzureWasteRepository();
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
      builder: (context) => AlertDialog(
        title: const Text('Clear all waste?'),
        content: const Text(
          'This clears every waste record currently shown in the dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const _DashboardNavigation(),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth < 370 ? 10.0 : 12.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: CustomScrollView(
                  key: const Key('dashboard_scroll_view'),
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 4, side, 12),
                      sliver: SliverList.list(
                        children: [
                          const _TopBar(),
                          const SizedBox(height: 8),
                          const _Greeting(),
                          const SizedBox(height: 16),
                          _DeviceCard(fillLevel: _fillLevel),
                          const SizedBox(height: 16),
                          _WasteInventoryCard(
                            entries: _entries,
                            loadError: _loadError,
                            onRetry: _loadWaste,
                            onClear: _confirmClearWaste,
                          ),
                          const SizedBox(height: 18),
                          const _RecyclingBanner(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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

    return SizedBox(
      key: const Key('device_card'),
      height: 180,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final artWidth = (constraints.maxWidth * .52)
              .clamp(168.0, 196.0)
              .toDouble();
          final detailsLeft = constraints.maxWidth * .52;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 32,
                bottom: 0,
                child: DecoratedBox(decoration: _cardDecoration()),
              ),
              Positioned(
                left: -4,
                top: -25,
                child: SizedBox(
                  width: artWidth,
                  height: 200,
                  child: Image.asset(
                    'assets/images/dustbin_3d.png',
                    key: const Key('dustbin_image'),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              Positioned(
                left: detailsLeft,
                right: 16,
                top: 32,
                bottom: 0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fill Level',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$percentage%',
                      key: const Key('fill_level_percentage'),
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 13),
                    _ProgressBar(value: fillLevel, color: levelColor),
                    const SizedBox(height: 10),
                    Text(
                      status,
                      key: const Key('fill_level_status'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: levelColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
          backgroundColor: const Color(0xFF1A313B),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
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
            style: TextStyle(color: Colors.white.withValues(alpha: .75)),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: .72),
                  ),
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
                  color: const Color(0xFF1B2C30),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFF243D43), width: .7),
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
                    : Image.asset(
                        entry.asset!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
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
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
              borderRadius: BorderRadius.circular(14),
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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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

class _RecyclingBanner extends StatelessWidget {
  const _RecyclingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('recycling_banner'),
      height: 102,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
          colors: [Color(0xFF148936), Color(0xFF08762D)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 17,
            bottom: 10,
            child: Icon(
              Icons.eco_rounded,
              size: 57,
              color: const Color(0xFF4DDD6A).withValues(alpha: .68),
            ),
          ),
          Positioned(
            left: 15,
            right: 72,
            top: 14,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'AI-verified waste\ninsights only.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.38,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.recycling_rounded,
                        size: 20,
                        color: Color(0xFF4DDD6A),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Tap verified waste for details.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: .83),
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

class _DashboardNavigation extends StatelessWidget {
  const _DashboardNavigation();

  static const items = <({String label, IconData icon})>[
    (label: 'Home', icon: Icons.home_outlined),
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
                    active: index == 0,
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
  const _NavigationItem({required this.item, required this.active});

  final ({String label, IconData icon}) item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.lime : const Color(0xFFA6AFB4);
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
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
      BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 5)),
    ],
  );
}
