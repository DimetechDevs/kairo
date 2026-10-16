import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what comes with the file import step.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(libraryProvider);
    final unmatched = files.where((f) => f.state == FileState.unmatched).toList();
    final byAnime = <int, List<LibraryFile>>{};
    for (final f in files.where((f) => f.animeId != null)) {
      byAnime.putIfAbsent(f.animeId!, () => []).add(f);
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          ScreenTitle(
            'Library',
            trailing: FilledButton.icon(
              onPressed: () => _comingSoon(context, 'Importing videos'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Import videos'),
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? EmptyState(
                    icon: Icons.video_library_outlined,
                    title: 'No videos yet',
                    message: 'Import episodes from your phone to watch them offline.',
                    action: FilledButton(
                      onPressed: () => _comingSoon(context, 'Importing videos'),
                      child: const Text('Import videos'),
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
                        for (final f in unmatched) _UnmatchedCard(file: f),
                        const SizedBox(height: KairoSpacing.xl),
                      ],
                      for (final entry in byAnime.entries)
                        if (ref.watch(animeProvider(entry.key)) case final anime?) ...[
                        _AnimeGroup(anime: anime, files: entry.value),
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

class _UnmatchedCard extends ConsumerWidget {
  const _UnmatchedCard({required this.file});

  final LibraryFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = file.suggestedAnimeId == null ? null : ref.watch(animeProvider(file.suggestedAnimeId!));
    return Container(
      padding: const EdgeInsets.all(KairoSpacing.md),
      decoration: BoxDecoration(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.panel),
        border: Border.all(color: KairoColors.info.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 44,
                decoration: BoxDecoration(color: KairoColors.surfaceRaised, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.movie_outlined, color: KairoColors.textMuted),
              ),
              const SizedBox(width: KairoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.fileName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(file.sizeLabel, style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Looks like '),
                TextSpan(
                  text: '${suggestion.shortTitle} · Episode ${file.suggestedEpisode}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ]),
              style: const TextStyle(fontSize: 13, color: Color(0xFFD9D6E8)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => ref.read(libraryProvider.notifier).confirmSuggestedMatch(file.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: KairoColors.info,
                      foregroundColor: KairoColors.background,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Confirm match'),
                  ),
                ),
                const SizedBox(width: KairoSpacing.sm),
                OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Manual matching comes with the file import step.')),
                  ),
                  child: const Text('Choose'),
                ),
              ],
            ),
          ],
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
          onTap: () => context.push(Routes.anime(anime.id)),
          child: Row(
            children: [
              SizedBox(width: 36, height: 52, child: CoverArt(anime: anime, radius: 6)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(anime.shortTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                    '${files.length} ${files.length == 1 ? 'file' : 'files'}',
                    style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final f in sorted) _FileRow(anime: anime, file: f),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.anime, required this.file});

  final Anime anime;
  final LibraryFile file;

  @override
  Widget build(BuildContext context) {
    final missing = file.state == FileState.missing;
    return Container(
      margin: const EdgeInsets.only(bottom: KairoSpacing.sm),
      padding: const EdgeInsets.all(10),
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
                Text(file.fileName, style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary)),
                Text(
                  missing ? 'File missing · moved or deleted' : 'Matched',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: missing ? KairoColors.accent : KairoColors.success,
                  ),
                ),
              ],
            ),
          ),
          if (missing)
            OutlinedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Relinking comes with the file import step.')),
              ),
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
        ],
      ),
    );
  }
}
