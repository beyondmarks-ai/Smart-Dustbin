import 'package:flutter/material.dart';

@immutable
class WasteEntry {
  const WasteEntry({
    required this.name,
    required this.classification,
    required this.count,
    this.asset,
    required this.accent,
    this.imageUrl,
    this.eventId,
    this.confidence = '0',
    this.material = '',
    this.category = '',
    this.recyclable = false,
    this.recyclingGuidance = '',
    this.contaminationNotes = '',
    this.reuseSafe = false,
    this.reuseIdeas = const [],
    this.safetyWarnings = const [],
    this.tags = const [],
    this.capturedAt,
    this.evidenceSummary = '',
    this.latitude,
    this.longitude,
    this.locationLabel = '',
    this.locationAddress = '',
    this.deviceId = '',
    this.itemIndex = 0,
    this.verificationStatus = 'unknown',
    this.locationAccuracy,
  });

  final String name;
  final String classification;
  final int count;
  final String? asset;
  final Color accent;
  final String? imageUrl;
  final String? eventId;
  final String confidence;
  final String material;
  final String category;
  final bool recyclable;
  final String recyclingGuidance;
  final String contaminationNotes;
  final bool reuseSafe;
  final List<String> reuseIdeas;
  final List<String> safetyWarnings;
  final List<String> tags;
  final String? capturedAt;
  final String evidenceSummary;
  final double? latitude;
  final double? longitude;
  final String locationLabel;
  final String locationAddress;
  final String deviceId;
  final int itemIndex;
  final String verificationStatus;
  final double? locationAccuracy;
  bool get needsReview => verificationStatus == 'review';
}
