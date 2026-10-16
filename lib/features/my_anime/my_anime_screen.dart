import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';

class MyAnimeScreen extends ConsumerStatefulWidget {
  const MyAnimeScreen({super.key});

  @override
  ConsumerState<MyAnimeScreen> createState() => _MyAnimeScreenState();
}

class _MyAnimeScreenState extends ConsumerState<MyAnimeScreen> {
  ListStatus _tab = ListStatus.watching;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(sortedWatchlistProvider);
    final visible = entries.where((e) => e.status == _tab).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenTitle(
            'My Anime',
            trailing: Text(
              '${entries.length} ${entries.length == 1 ? 'title' : 'titles'}',
              style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
            ),
          ),
          HorizontalStrip(
            spacing: KairoSpacing.sm,
            children: [
              for (final s in ListStatus.values)
                FilterPill(
                  label: s.label,
                  trailing: '${entries.where((e) => e.status == s).length}',
                  selected: s == _tab,
                  onTap: () => setState(() => _tab = s),
                ),
            ],
          ),
          const SizedBox(height: KairoSpacing.md),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Nothing here yet',
                    message: 'Titles you mark as ${_tab.label.toLowerCase()} will show up here.',
                    action: FilledButton(
                      onPressed: () => StatefulNavigationShell.of(context).goBranch(1),
                      child: const Text('Browse anime'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 4, KairoSpacing.gutter, KairoSpacing.xxl),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ListRow(key: ValueKey(visible[i].animeId), entry: visible[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListRow extends ConsumerWidget {
  const _ListRow({super.key, required this.entry});

  final WatchEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anime = entry.anime;
    final total = anime.episodes;
    final isWatching = entry.status == ListStatus.watching;
    final label = switch (entry.status) {
      ListStatus.completed => 'Completed · ${anime.episodesLabel}',
      ListStatus.watching || ListStatus.paused || ListStatus.dropped => 'Ep ${entry.watched} / ${total ?? '?'}',
      ListStatus.planned => [
        anime.formatLabel,
        anime.episodesLabel,
        if (anime.year != null) '${anime.year}',
      ].join(' · '),
    };
    final progressBase = total ?? (anime.airedEpisodes > 0 ? anime.airedEpisodes : null);

    return Material(
      color: KairoColors.surface,
      borderRadius: BorderRadius.circular(KairoRadii.panel),
      child: InkWell(
        borderRadius: BorderRadius.circular(KairoRadii.panel),
        onTap: () => context.push(Routes.anime(anime.id)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(width: 60, height: 86, child: CoverArt(anime: anime, radius: 8)),
              const SizedBox(width: KairoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                          ),
                        ),
                        if (anime.score != null) ...[
                          const SizedBox(width: 8),
                          ScoreLabel(score: anime.score!, size: 12),
                        ],
                      ],
                    ),
                    if (anime.nextAiring != null && entry.status != ListStatus.completed)
                      Text(anime.nextAiring!.label(), style: const TextStyle(fontSize: 12, color: KairoColors.success)),
                    if (entry.status != ListStatus.planned && progressBase != null) ...[
                      const SizedBox(height: 6),
                      ProgressLine(value: entry.watched / progressBase, color: anime.accent),
                    ],
                  ],
                ),
              ),
              if (isWatching && (total == null || entry.watched < total)) ...[
                const SizedBox(width: KairoSpacing.sm),
                Tooltip(
                  message: 'Mark episode ${entry.watched + 1} watched',
                  child: OutlinedButton(
                    onPressed: () => ref.read(watchlistProvider.notifier).markNextWatched(anime),
                    style: OutlinedButton.styleFrom(
                      shape: const CircleBorder(),
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                      backgroundColor: KairoColors.surfaceRaised,
                    ),
                    child: const Text('+1', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
