import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/filename_parser.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/match_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;

  Future<void> _import() async {
    try {
      final picked = await ref.read(documentsProvider).pickVideos();
      if (picked.isEmpty || !mounted) return;
      setState(() => _importing = true);
      await ref.read(libraryProvider.notifier).importPicked(picked);
    } on PlatformException catch (e) {
      if (mounted) _snack("Couldn't open the file picker: ${e.message}");
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _addStream() async {
    final match = await showMatchSheet(context, title: 'Which show is the link for?');
    if (match == null || !mounted) return;
    final (anime, episode) = match;
    await addWatchLinkFor(context, ref, anime, episode);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(libraryProvider);
    final unmatched = files.where((f) => f.anime == null).toList();
    final byAnime = <int, List<LibraryFile>>{};
    for (final f in files.where((f) => f.anime != null)) {
      byAnime.putIfAbsent(f.animeId!, () => []).add(f);
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          ScreenTitle(
            'Library',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FilledButton.icon(
                    onPressed: _importing ? null : _import,
                    icon: _importing
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_rounded),
                    label: const Text('Import', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  color: KairoColors.surfaceRaised,
                  onSelected: (v) {
                    if (v == 'stream') _addStream();
                    if (v == 'check') ref.read(libraryProvider.notifier).checkMissing();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'stream', child: Text('Add stream URL')),
                    PopupMenuItem(value: 'check', child: Text('Check for missing files')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? EmptyState(
                    icon: Icons.video_library_outlined,
                    title: 'No videos yet',
                    message:
                        'Import episodes from your phone to watch them offline, or add a stream URL from your own media server.',
                    action: Wrap(
                      spacing: KairoSpacing.sm,
                      runSpacing: KairoSpacing.sm,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(onPressed: _import, icon: const Icon(Icons.add_rounded), label: const Text('Import videos')),
                        OutlinedButton.icon(
                          onPressed: _addStream,
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('Add stream URL'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 4, KairoSpacing.gutter, KairoSpacing.xxl),
                    children: [
                      if (unmatched.isNotEmpty) ...[
                        Text(
                          'Needs matching · ${unmatched.length}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KairoColors.info),
                        ),
                        const SizedBox(height: 10),
                        for (final f in unmatched) _UnmatchedCard(key: ValueKey(f.id), file: f),
                        const SizedBox(height: KairoSpacing.xl),
                      ],
                      for (final entry in byAnime.entries) ...[
                        _AnimeGroup(anime: entry.value.first.anime!, files: entry.value),
                        const SizedBox(height: KairoSpacing.xl),
                      ],
                      const Text(
                        'Videos stay where they are on your phone. Kairo only remembers where to find them.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> _chooseMatch(BuildContext context, WidgetRef ref, LibraryFile file) async {
  final guess = parseVideoName(file.fileName);
  final match = await showMatchSheet(
    context,
    initialQuery: file.suggestedAnime?.title ?? file.anime?.title ?? guess.title,
    initialEpisode: file.episode ?? file.suggestedEpisode ?? guess.episode ?? 1,
  );
  if (match == null) return;
  ref.read(libraryProvider.notifier).matchTo(file.id, match.$1, match.$2);
}

Future<void> _relink(WidgetRef ref, LibraryFile file) async {
  final doc = await ref.read(documentsProvider).pickVideo();
  if (doc != null) ref.read(libraryProvider.notifier).relink(file.id, doc);
}

class _UnmatchedCard extends ConsumerWidget {
  const _UnmatchedCard({super.key, required this.file});

  final LibraryFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = file.suggestedAnime;
    final missing = file.state == FileState.missing;
    return Container(
      margin: const EdgeInsets.only(bottom: KairoSpacing.sm),
      padding: const EdgeInsets.all(KairoSpacing.md),
      decoration: BoxDecoration(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.panel),
        border: Border.all(color: (missing ? KairoColors.accent : KairoColors.info).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 44,
                child: suggestion != null
                    ? CoverArt(anime: suggestion, banner: true, radius: 8)
                    : DecoratedBox(
                        decoration: BoxDecoration(color: KairoColors.surfaceRaised, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.movie_outlined, color: KairoColors.textMuted),
                      ),
              ),
              const SizedBox(width: KairoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      missing ? 'File missing · moved or deleted' : file.sizeLabel,
                      style: TextStyle(fontSize: 12, color: missing ? KairoColors.accent : KairoColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _FileMenu(file: file),
            ],
          ),
          const SizedBox(height: 10),
          if (suggestion != null)
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Looks like '),
                TextSpan(
                  text: '${suggestion.title} · Episode ${file.suggestedEpisode}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ]),
              style: const TextStyle(fontSize: 13, color: Color(0xFFD9D6E8)),
            )
          else
            const Text("Couldn't tell which show this is.", style: TextStyle(fontSize: 13, color: KairoColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (suggestion != null) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: () => ref.read(libraryProvider.notifier).confirmSuggestedMatch(file.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: KairoColors.info,
                      foregroundColor: KairoColors.background,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Confirm', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: KairoSpacing.sm),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _chooseMatch(context, ref, file),
                  child: Text(suggestion != null ? 'Choose' : 'Choose show', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimeGroup extends StatelessWidget {
  const _AnimeGroup({required this.anime, required this.files});

  final Anime anime;
  final List<LibraryFile> files;

  @override
  Widget build(BuildContext context) {
    final sorted = [...files]..sort((a, b) => a.episode!.compareTo(b.episode!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(KairoRadii.card),
          onTap: () => context.push(Routes.anime(anime.id)),
          child: Row(
            children: [
              SizedBox(width: 36, height: 52, child: CoverArt(anime: anime, radius: 6)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.shortTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${files.length} ${files.length == 1 ? 'video' : 'videos'}',
                      style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: KairoColors.textMuted),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final f in sorted) _FileRow(key: ValueKey(f.id), anime: anime, file: f),
      ],
    );
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({super.key, required this.anime, required this.file});

  final Anime anime;
  final LibraryFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = file.state == FileState.missing;
    final progress = ref.watch(progressProvider)[(anime.id, file.episode!)];
    final (label, color) = switch ((missing, progress)) {
      (true, _) => ('File missing · moved or deleted', KairoColors.accent),
      (false, final PlaybackProgress p) when p.finished => ('Watched', KairoColors.success),
      (false, final PlaybackProgress p) => ('${(p.remaining.inSeconds / 60).ceil()} min left', KairoColors.info),
      _ => (file.isStream ? 'Stream' : 'Ready to play', KairoColors.success),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: KairoSpacing.sm),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.card),
        border: Border.all(color: missing ? KairoColors.accent.withValues(alpha: 0.5) : const Color(0xFF2A2740)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Episode ${file.episode}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text(
                  [file.fileName, if (file.sizeLabel.isNotEmpty) file.sizeLabel].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                ),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                if (progress != null && !progress.finished && !missing) ...[
                  const SizedBox(height: 4),
                  ProgressLine(value: progress.fraction, color: KairoColors.accent, height: 3),
                ],
              ],
            ),
          ),
          if (missing)
            OutlinedButton(
              onPressed: () => _relink(ref, file),
              style: OutlinedButton.styleFrom(
                foregroundColor: KairoColors.accent,
                side: const BorderSide(color: KairoColors.accent),
              ),
              child: const Text('Relink'),
            )
          else
            IconButton.filledTonal(
              tooltip: 'Play episode ${file.episode}',
              onPressed: () => context.push(Routes.player(anime.id, file.episode!)),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          _FileMenu(file: file),
        ],
      ),
    );
  }
}

class _FileMenu extends ConsumerWidget {
  const _FileMenu({required this.file});

  final LibraryFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Options',
      color: KairoColors.surfaceRaised,
      icon: const Icon(Icons.more_vert_rounded, color: KairoColors.textSecondary),
      onSelected: (v) async {
        switch (v) {
          case 'match':
            await _chooseMatch(context, ref, file);
          case 'relink':
            await _relink(ref, file);
          case 'remove':
            ref.read(libraryProvider.notifier).remove(file.id);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'match', child: Text(file.anime == null ? 'Choose show' : 'Change show or episode')),
        if (!file.isStream) const PopupMenuItem(value: 'relink', child: Text('Relink file')),
        const PopupMenuItem(
          value: 'remove',
          child: Text('Remove from Kairo', style: TextStyle(color: KairoColors.accent)),
        ),
      ],
    );
  }
}
