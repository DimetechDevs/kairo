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
    final entries = ref.watch(watchlistProvider).values.toList();
    final visible = entries.where((e) => e.status == _tab).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenTitle('My Anime'),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
              itemCount: ListStatus.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: KairoSpacing.sm),
              itemBuilder: (_, i) {
                final s = ListStatus.values[i];
                return FilterPill(
                  label: s.label,
                  trailing: '${entries.where((e) => e.status == s).length}',
                  selected: s == _tab,
                  onTap: () => setState(() => _tab = s),
                );
              },
            ),
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
                    itemBuilder: (_, i) => _ListRow(entry: visible[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListRow extends ConsumerWidget {
  const _ListRow({required this.entry});

  final WatchEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anime = ref.watch(animeProvider(entry.animeId));
    final isWatching = entry.status == ListStatus.watching;
    final label = switch (entry.status) {
      ListStatus.completed => 'Completed · ${anime.episodes} episodes',
      ListStatus.watching || ListStatus.paused => 'Ep ${entry.watched} / ${anime.episodes}',
      _ => '${anime.episodes} episodes',
    };

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
              SizedBox(width: 56, height: 80, child: CoverArt(anime: anime, radius: 8)),
              const SizedBox(width: KairoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(anime.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
                    const SizedBox(height: 4),
                    Text(label, style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary)),
                    const SizedBox(height: 6),
                    ProgressLine(value: entry.watched / anime.episodes),
                  ],
                ),
              ),
              if (isWatching && entry.watched < anime.episodes) ...[
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
