import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/settings.dart';
import '../data/watch_links.dart';
import 'playback_controller.dart';

/// Plays an imported file or stream for an episode in Kairo's player.
Future<void> playEpisode(BuildContext context, WidgetRef ref, int animeId, int episode) async {
  final ok = await ref.read(playbackProvider.notifier).playEpisode(animeId, episode);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Episode $episode isn't in your library. Import the file or add a link first.")),
    );
  }
}

/// Opens a streaming-site link the way the user prefers: in Kairo's player browser, or in the
/// service's own app (always for services that refuse to play inside other apps).
Future<void> openWatchLink(BuildContext context, WidgetRef ref, String url, {int? animeId, int? episode}) async {
  final service = serviceFor(url);
  if (service?.blocksInAppPlayback == true || !ref.read(settingsProvider).openLinksInApp) {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open that link")));
    }
    return;
  }
  await ref.read(playbackProvider.notifier).openWeb(url, animeId: animeId, episode: episode);
}
