import 'package:flutter/material.dart';
import 'app_preferences.dart';
import 'detection_location.dart';
import 'camera_wifi_setup.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _text = TextEditingController();
  bool _posting = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a review before posting.')),
      );
      return;
    }
    setState(() => _posting = true);
    try {
      await appPreferences.postReview(_text.text);
      _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your review. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appPreferences,
    builder: (context, _) {
      final reviews = appPreferences.reviews;
      final counts = [
        for (final type in Sentiment.values)
          reviews.where((r) => r.sentiment == type).length,
      ];
      const colors = [Color(0xFF2C9851), Color(0xFF78909C), Color(0xFFE85055)];
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Feedback & Reviews',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overall sentiment',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 22),
                  if (reviews.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 14,
                        child: Row(
                          children: [
                            for (var i = 0; i < 3; i++)
                              if (counts[i] > 0)
                                Expanded(
                                  flex: counts[i],
                                  child: ColoredBox(
                                    color: colors[i],
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                reviews.isEmpty
                                    ? '—'
                                    : '${(counts[i] * 100 / reviews.length).round()}%',
                                style: TextStyle(
                                  color: colors[i],
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(['Positive', 'Neutral', 'Negative'][i]),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('${reviews.length} reviews on this device'),
                  const Text(
                    'Estimated on device using text rules. Reviews stay on this phone.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Leave a review',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('review_input'),
                    controller: _text,
                    maxLength: 1000,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Tell us what you think…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _posting ? null : _post,
                      child: Text(_posting ? 'Saving…' : 'Post review'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Recent reviews', style: Theme.of(context).textTheme.titleLarge),
          if (reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Be the first to leave a review.'),
            ),
          for (final review in reviews)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(child: Icon(Icons.person_outline)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'You',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            detectedTime(review.at.toIso8601String()),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Chip(
                            label: Text(review.sentiment.name),
                            labelStyle: TextStyle(
                              color: colors[review.sentiment.index],
                            ),
                            backgroundColor: colors[review.sentiment.index]
                                .withValues(alpha: .12),
                          ),
                          Text(review.text),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.cloudOnline,
    required this.checking,
    required this.onRefresh,
    required this.onEmpty,
  });
  final bool cloudOnline;
  final bool checking;
  final VoidCallback onRefresh;
  final VoidCallback onEmpty;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appPreferences,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('General', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<ThemeMode>(
                  isExpanded: true,
                  initialValue: appPreferences.themeMode,
                  decoration: const InputDecoration(labelText: 'Screen theme'),
                  items: [
                    for (final mode in ThemeMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(switch (mode) {
                          ThemeMode.system => 'Use system setting',
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                        }),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) appPreferences.setTheme(mode);
                  },
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    cloudOnline
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text(
                    checking
                        ? 'Checking connection…'
                        : cloudOnline
                        ? 'Cloud service online'
                        : 'Cloud service offline',
                  ),
                  subtitle: const Text(
                    'Connection to the waste data service. Camera status is available in Camera setup.',
                  ),
                  trailing: IconButton(
                    onPressed: onRefresh,
                    tooltip: 'Check connection',
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Single bin',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text('Estimated capacity: ${appPreferences.capacity} items'),
                const Text(
                  'Fill level is estimated from item count; it is not a physical volume measurement.',
                ),
                TextButton(
                  onPressed: () => _capacity(context),
                  child: const Text('Change capacity'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onEmpty,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Bin emptied · reset fill level'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Resetting the fill level preserves detection history and reports.',
                  style: TextStyle(fontSize: 12),
                ),
                if (appPreferences.emptiedAt != null)
                  Text(
                    'Last reset: ${detectedTime(appPreferences.emptiedAt!.toIso8601String())}',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Camera & mobile hotspot',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Keep the camera on your 2.4 GHz vivo hotspot with mobile data enabled. The camera uploads detections to Azure automatically.\n\nTo attach a location, stand beside the bin, use your phone location and save it to the camera. Its IP and setup code are printed in Serial Monitor at 115200 baud.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CameraWifiSetup(),
                    ),
                  ),
                  icon: const Icon(Icons.wifi),
                  label: const Text('Change camera Wi-Fi'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Camera setup')),
                        body: const LocationPage(entries: []),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.settings_input_antenna),
                  label: const Text('Configure camera location'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The saved location survives camera restarts and applies to future captures. Reconfigure it after moving the bin.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('EcoSort AI · Single-camera waste intelligence'),
        ),
      ],
    ),
  );
  Future<void> _capacity(BuildContext context) async {
    final controller = TextEditingController(
      text: appPreferences.capacity.toString(),
    );
    final form = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bin capacity'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Estimated item capacity',
            ),
            validator: (text) {
              final n = int.tryParse(text ?? '');
              return n == null || n < 1 || n > 10000
                  ? 'Enter 1 to 10,000 items'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(controller.text));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) await appPreferences.setCapacity(value);
    // Dialog transitions may still reference the controller until the next frame.
  }
}
