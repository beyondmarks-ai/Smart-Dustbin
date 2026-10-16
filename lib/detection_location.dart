import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'camera_location_setup.dart';

import 'dashboard_data.dart';

String detectedTime(String? raw) {
  final date = DateTime.tryParse(raw ?? '')?.toLocal();
  if (date == null) return 'Time unavailable';
  final now = DateTime.now();
  final day =
      date.year == now.year && date.month == now.month && date.day == now.day
      ? 'Today'
      : '${date.day}/${date.month}/${date.year}';
  return '$day, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

bool hasCoordinates(WasteEntry entry) =>
    entry.latitude != null &&
    entry.longitude != null &&
    entry.latitude!.isFinite &&
    entry.longitude!.isFinite &&
    entry.latitude!.abs() <= 90 &&
    entry.longitude!.abs() <= 180;

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    /* Give a useful action failure below. */
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open this link. Try again when connected.'),
      ),
    );
  }
}

class CaptureLocationCard extends StatelessWidget {
  const CaptureLocationCard({super.key, required this.entry});
  final WasteEntry entry;
  @override
  Widget build(BuildContext context) {
    final valid = hasCoordinates(entry);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Capture location', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        if (valid) ...[
          Text(
            '${entry.latitude!.abs().toStringAsFixed(6)}° ${entry.latitude! >= 0 ? 'N' : 'S'}, ${entry.longitude!.abs().toStringAsFixed(6)}° ${entry.longitude! >= 0 ? 'E' : 'W'}',
            key: const Key('capture_coordinates'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (entry.locationAccuracy != null &&
              entry.locationAccuracy!.isFinite &&
              entry.locationAccuracy! >= 0)
            Text(
              'Location accuracy: about ${entry.locationAccuracy!.round()} m',
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 170,
              child: FlutterMap(
                key: ValueKey('${entry.latitude},${entry.longitude}'),
                options: MapOptions(
                  initialCenter: LatLng(entry.latitude!, entry.longitude!),
                  initialZoom: 16,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.smart_dustbin',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(entry.latitude!, entry.longitude!),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap contributors',
                        onTap: () => openExternal(
                          context,
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => openExternal(
                context,
                Uri.https('www.google.com', '/maps/search/', {
                  'api': '1',
                  'query': '${entry.latitude},${entry.longitude}',
                }),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open in Maps'),
            ),
          ),
        ] else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Location was not recorded for this capture. Set the camera location for future detections.',
            ),
          ),
        if (entry.locationLabel.isNotEmpty)
          Text(
            entry.locationLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        if (entry.locationAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(entry.locationAddress),
          ),
        if (valid)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Fixed camera location at capture time',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class DetectionDetailsPage extends StatelessWidget {
  const DetectionDetailsPage({super.key, required this.entry});
  final WasteEntry entry;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detection details')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 1.7,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: entry.imageUrl != null
                      ? Image.network(
                          entry.imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => const Center(
                            child: Icon(Icons.broken_image_outlined, size: 52),
                          ),
                        )
                      : entry.asset != null
                      ? Image.asset(entry.asset!, fit: BoxFit.contain)
                      : const Center(
                          child: Icon(Icons.image_outlined, size: 52),
                        ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Chip(label: Text(entry.name)),
                ),
                Positioned(
                  right: 12,
                  bottom: 8,
                  child: Chip(
                    label: Text('${entry.confidence}%'),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (entry.needsReview)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Needs review: the AI is uncertain. Confirm the item before following sorting guidance.',
                      style: TextStyle(color: Color(0xFFB66A00)),
                    ),
                  ),
                Chip(
                  label: Text(
                    entry.category == 'organic'
                        ? 'Organic'
                        : entry.recyclable
                        ? 'Recyclable'
                        : 'Non-recyclable',
                  ),
                ),
                _line(context, 'Confidence', '${entry.confidence}%'),
                _line(context, 'Detected at', detectedTime(entry.capturedAt)),
                const Divider(height: 30),
                CaptureLocationCard(entry: entry),
                if (entry.material.isNotEmpty)
                  _line(context, 'Material', entry.material),
                if (entry.recyclingGuidance.isNotEmpty)
                  _line(context, 'Recycling guidance', entry.recyclingGuidance),
                if (entry.contaminationNotes.isNotEmpty)
                  _line(context, 'Contamination', entry.contaminationNotes),
                if (entry.reuseSafe && entry.reuseIdeas.isNotEmpty)
                  _line(context, 'Reuse ideas', entry.reuseIdeas.join('\n')),
                if (entry.safetyWarnings.isNotEmpty)
                  _line(context, 'Safety', entry.safetyWarnings.join('\n')),
                if (entry.evidenceSummary.isNotEmpty)
                  _line(context, 'AI evidence', entry.evidenceSummary),
                if (entry.deviceId.isNotEmpty)
                  _line(context, 'Camera', entry.deviceId),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _line(BuildContext context, String label, String value) {
    if (label == 'Confidence' || label == 'Detected at') {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class LocationPage extends StatefulWidget {
  const LocationPage({super.key, required this.entries});
  final List<WasteEntry> entries;
  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Camera location',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const CameraLocationSetup(),
      const SizedBox(height: 22),
      Text(
        'Recent capture locations',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (widget.entries.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'No detections yet. Location will appear with each captured event.',
          ),
        ),
      for (final entry in widget.entries.take(20))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(detectedTime(entry.capturedAt)),
                const SizedBox(height: 16),
                CaptureLocationCard(entry: entry),
              ],
            ),
          ),
        ),
    ],
  );
}
