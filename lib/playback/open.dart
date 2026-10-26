import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_controller.dart';

/// Plays an episode from the Kairo API, or says why it can't.
Future<void> playEpisode(BuildContext context, WidgetRef ref, int animeId, int episode) async {
  final error = await ref.read(playbackProvider.notifier).playEpisode(animeId, episode);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }
}
