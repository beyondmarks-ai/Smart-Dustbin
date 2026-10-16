import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appPreferences = AppPreferences();

class AppPreferences extends ChangeNotifier with WidgetsBindingObserver {
  bool _observing = false;
  @override
  void didChangePlatformBrightness() {
    notifyListeners();
  }

  SharedPreferences? _storage;
  ThemeMode themeMode = ThemeMode.system;
  int capacity = 50;
  DateTime? emptiedAt;
  bool session = false;
  final List<LocalReview> reviews = [];

  Future<void> load() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _storage = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.firstWhere(
      (v) => v.name == _storage!.getString('theme'),
      orElse: () => ThemeMode.system,
    );
    capacity = (_storage!.getInt('capacity') ?? 50).clamp(1, 10000);
    emptiedAt = DateTime.tryParse(_storage!.getString('emptiedAt') ?? '');
    session = _storage!.getBool('session') ?? false;
    reviews.clear();
    for (final raw in _storage!.getStringList('reviews') ?? <String>[]) {
      try {
        reviews.add(
          LocalReview.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } on FormatException {
        continue;
      }
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    await _storage?.setString('theme', mode.name);
    themeMode = mode;
    notifyListeners();
  }

  Future<void> setCapacity(int value) async {
    await _storage?.setInt('capacity', value);
    capacity = value;
    notifyListeners();
  }

  Future<void> emptyBin() async {
    final now = DateTime.now();
    await _storage?.setString('emptiedAt', now.toIso8601String());
    emptiedAt = now;
    notifyListeners();
  }

  Future<void> setSession(bool value) async {
    await _storage?.setBool('session', value);
    session = value;
    notifyListeners();
  }

  Future<void> postReview(String text) async {
    final review = LocalReview(
      text.trim(),
      DateTime.now(),
      classifySentiment(text),
    );
    final updated = [review, ...reviews];
    await _storage?.setStringList(
      'reviews',
      updated.map((r) => jsonEncode(r.toJson())).toList(),
    );
    reviews.insert(0, review);
    notifyListeners();
  }
}

enum Sentiment { positive, neutral, negative }

// A small, transparent offline estimator; it does not upload review text.
Sentiment classifySentiment(String text) {
  const positive = {
    'good',
    'great',
    'excellent',
    'love',
    'happy',
    'fast',
    'helpful',
    'easy',
    'amazing',
    'accurate',
    'perfect',
    'reliable',
    'useful',
    'works',
  };
  const negative = {
    'bad',
    'poor',
    'hate',
    'slow',
    'crash',
    'crashed',
    'broken',
    'wrong',
    'error',
    'difficult',
    'useless',
    'failed',
    'terrible',
    'unreliable',
    'disappointed',
  };
  final tokens = RegExp(
    r"[a-z]+(?:'[a-z]+)?|[.!?,;]",
  ).allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
  var score = 0;
  for (var i = 0; i < tokens.length; i++) {
    var weight = positive.contains(tokens[i])
        ? 1
        : negative.contains(tokens[i])
        ? -1
        : 0;
    final recent = tokens.sublist((i - 3).clamp(0, i), i);
    final boundary = recent.lastIndexWhere(
      (t) => {'.', '!', '?', ',', ';'}.contains(t),
    );
    final preceding = recent.sublist(boundary + 1);
    if (preceding.any(
      (t) => {
        'not',
        'never',
        'no',
        "isn't",
        "wasn't",
        "don't",
        "doesn't",
      }.contains(t),
    )) {
      weight = -weight;
    }
    score += weight;
  }
  return score > 0
      ? Sentiment.positive
      : score < 0
      ? Sentiment.negative
      : Sentiment.neutral;
}

class LocalReview {
  const LocalReview(this.text, this.at, this.sentiment);
  final String text;
  final DateTime at;
  final Sentiment sentiment;
  Map<String, dynamic> toJson() => {
    'text': text,
    'at': at.toIso8601String(),
    'sentiment': sentiment.name,
  };
  factory LocalReview.fromJson(Map<String, dynamic> json) => LocalReview(
    json['text'] as String,
    DateTime.parse(json['at'] as String),
    Sentiment.values.byName(json['sentiment'] as String),
  );
}
