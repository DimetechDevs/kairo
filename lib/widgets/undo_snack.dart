import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/providers.dart';

/// Shows [text] with an Undo button for a few seconds. [onExpired] runs when
/// the bar closes any other way, so cleanup waits until Undo is gone.
void showUndoSnack(BuildContext context, String text, {required VoidCallback onUndo, VoidCallback? onExpired}) {
  final controller = ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar();
  controller
      .showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ))
      .closed
      .then((reason) {
    if (reason != SnackBarClosedReason.action) onExpired?.call();
  });
}

/// Takes a title off the list with an Undo option.
void removeFromListWithUndo(BuildContext context, WidgetRef ref, Anime anime) {
  final notifier = ref.read(watchlistProvider.notifier);
  final entry = notifier.remove(anime.id);
  if (entry == null) return;
  showUndoSnack(context, 'Removed ${anime.title} from your list', onUndo: () => notifier.restore(entry));
}

/// Removes a library file or saved link with an Undo option.
void removeFileWithUndo(BuildContext context, WidgetRef ref, String fileId) {
  final notifier = ref.read(libraryProvider.notifier);
  final file = notifier.remove(fileId);
  if (file == null) return;
  showUndoSnack(
    context,
    file.isStream ? 'Link removed' : 'Removed ${file.fileName}',
    onUndo: () => notifier.restore(file),
    onExpired: () => notifier.release(file),
  );
}
