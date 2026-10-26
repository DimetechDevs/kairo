import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Language choices for subtitles and audio: mpv language codes and a label.
const subtitleLanguages = {
  'en': 'English',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'fr': 'French',
  'de': 'German',
  'ja': 'Japanese',
  'off': 'Off',
};
const audioLanguages = {'ja': 'Japanese', 'en': 'English', 'auto': "The file's default"};

/// Player and app preferences, saved on the phone.
class KairoSettings {
  const KairoSettings({
    this.speed = 1.0,
    this.autoNext = true,
    this.skipIntro = true,
    this.skipSeconds = 85,
    this.watchedAt = 0.9,
    this.subtitleLanguage = 'en',
    this.audioLanguage = 'ja',
    this.airingAlerts = true,
  });

  final double speed;
  final bool autoNext;
  final bool skipIntro;
  final int skipSeconds;

  /// Share of an episode after which it counts as watched (0.8–0.95).
  final double watchedAt;

  /// A key of [subtitleLanguages].
  final String subtitleLanguage;

  /// A key of [audioLanguages].
  final String audioLanguage;

  /// Notify when a new episode of something on the Watching or Planned list airs.
  final bool airingAlerts;


  KairoSettings copyWith({
    double? speed,
    bool? autoNext,
    bool? skipIntro,
    int? skipSeconds,
    double? watchedAt,
    String? subtitleLanguage,
    String? audioLanguage,
    bool? airingAlerts,
  }) =>
      KairoSettings(
        speed: speed ?? this.speed,
        autoNext: autoNext ?? this.autoNext,
        skipIntro: skipIntro ?? this.skipIntro,
        skipSeconds: skipSeconds ?? this.skipSeconds,
        watchedAt: watchedAt ?? this.watchedAt,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        audioLanguage: audioLanguage ?? this.audioLanguage,
        airingAlerts: airingAlerts ?? this.airingAlerts,
      );

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'autoNext': autoNext,
        'skipIntro': skipIntro,
        'skipSeconds': skipSeconds,
        'watchedAt': watchedAt,
        'subtitleLanguage': subtitleLanguage,
        'audioLanguage': audioLanguage,
        'airingAlerts': airingAlerts,
      };

  /// Unknown or missing keys fall back to the defaults, so older saves keep working.
  factory KairoSettings.fromJson(Map<String, dynamic> j) {
    const d = KairoSettings();
    return KairoSettings(
      speed: (j['speed'] as num?)?.toDouble() ?? d.speed,
      autoNext: j['autoNext'] as bool? ?? d.autoNext,
      skipIntro: j['skipIntro'] as bool? ?? d.skipIntro,
      skipSeconds: j['skipSeconds'] as int? ?? d.skipSeconds,
      watchedAt: (j['watchedAt'] as num?)?.toDouble() ?? d.watchedAt,
      subtitleLanguage: subtitleLanguages.containsKey(j['subtitleLanguage']) ? j['subtitleLanguage'] as String : d.subtitleLanguage,
      audioLanguage: audioLanguages.containsKey(j['audioLanguage']) ? j['audioLanguage'] as String : d.audioLanguage,
      airingAlerts: j['airingAlerts'] as bool? ?? d.airingAlerts,
    );
  }
}

class SettingsNotifier extends Notifier<KairoSettings> {
  static const _key = 'settings.v1';

  @override
  KairoSettings build() {
    final raw = ref.watch(prefsProvider).getString(_key);
    if (raw == null) return const KairoSettings();
    try {
      return KairoSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const KairoSettings();
    }
  }

  void update(KairoSettings Function(KairoSettings s) change) {
    state = change(state);
    ref.read(prefsProvider).setString(_key, jsonEncode(state.toJson()));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, KairoSettings>(SettingsNotifier.new);
