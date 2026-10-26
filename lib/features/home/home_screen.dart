import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../playback/open.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/poster_card.dart';
import '../discover/discover_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _seeAll(BuildContext context, WidgetRef ref, DiscoverSort sort) {
    ref.read(discoverRequestProvider.notifier).open(sort);
    StatefulNavigationShell.of(context).goBranch(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final resume = ref.watch(resumeListProvider);
    final resuming = {for (final (p, _) in resume) p.animeId};
    final watching = ref
        .watch(sortedWatchlistProvider)
        .where((e) => e.status == ListStatus.watching && !resuming.contains(e.animeId))
        .toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(homeFeedProvider.future),
        child: ListView(
          padding: const EdgeInsets.only(bottom: KairoSpacing.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, KairoSpacing.lg, KairoSpacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(text: 'Kai'),
                          TextSpan(
                            text: 'ro',
                            style: TextStyle(color: KairoColors.primary),
                          ),
                        ],
                      ),
                      style: KairoTheme.display(context),
                      semanticsLabel: 'Kairo',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () => StatefulNavigationShell.of(context).goBranch(1),
                    icon: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KairoSpacing.lg),
            switch (feed) {
              AsyncValue(:final value?) => _FeaturedCarousel(items: value.trending.take(6).toList()),
              AsyncValue(:final error?) => SizedBox(
                height: 300,
                child: ErrorState(error: error, onRetry: () => ref.invalidate(homeFeedProvider)),
              ),
              _ => Padding(
                padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                child: Skeleton(height: _heroHeight(context), radius: KairoRadii.hero),
              ),
            },
            if (resume.isNotEmpty || watching.isNotEmpty) ...[
              const SizedBox(height: KairoSpacing.xl),
              SectionHeader(
                'Continue watching',
                actionLabel: 'My list',
                onAction: () => StatefulNavigationShell.of(context).goBranch(2),
              ),
              const SizedBox(height: KairoSpacing.xs),
              HorizontalStrip(
                children: [
                  for (final (p, f) in resume) _ResumeCard(progress: p, file: f),
                  for (final e in watching) _ContinueCard(entry: e),
                ],
              ),
            ],
            const SizedBox(height: KairoSpacing.lg),
            if (feed.value case final value?) ...[
              PosterRow(
                title: 'Popular this season',
                items: value.season,
                onSeeAll: () => _seeAll(context, ref, DiscoverSort.season),
              ),
              const SizedBox(height: KairoSpacing.lg),
              PosterRow(
                title: 'Trending now',
                items: value.trending.skip(6).toList(),
                onSeeAll: () => _seeAll(context, ref, DiscoverSort.trending),
              ),
              const SizedBox(height: KairoSpacing.lg),
              PosterRow(
                title: 'All-time popular',
                items: value.popular,
                onSeeAll: () => _seeAll(context, ref, DiscoverSort.popular),
              ),
              const SizedBox(height: KairoSpacing.lg),
              PosterRow(
                title: 'Top rated',
                items: value.topRated,
                onSeeAll: () => _seeAll(context, ref, DiscoverSort.topRated),
              ),
            ] else if (feed.isLoading) ...[
              const PosterRowSkeleton(),
              const SizedBox(height: KairoSpacing.lg),
              const PosterRowSkeleton(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Swipeable trending titles at the top of Home. Moves on by itself every few seconds.
class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({required this.items});

  final List<Anime> items;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  Timer? _auto;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartAuto();
  }

  void _restartAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_controller.hasClients || widget.items.length < 2) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(next, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: _heroHeight(context),
          child: NotificationListener<ScrollStartNotification>(
            // Pause the auto-advance while the user is swiping.
            onNotification: (n) {
              if (n.dragDetails != null) _restartAuto();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _FeaturedCard(anime: widget.items[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: KairoSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index ? KairoColors.primarySoft : KairoColors.outline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FeaturedCard extends ConsumerWidget {
  const _FeaturedCard({required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(watchlistProvider)[anime.id];
    final meta = [
      if (anime.year != null) '${anime.year}',
      anime.formatLabel,
      anime.episodesLabel,
      ...anime.genres.take(2),
    ].join(' · ');

    return GestureDetector(
      onTap: () => context.push(Routes.anime(anime.id)),
      child: CoverArt(
        anime: anime,
        banner: true,
        radius: KairoRadii.hero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, anime.palette.last.withValues(alpha: 0.85), KairoColors.background],
              stops: const [0.15, 0.62, 1],
            ),
          ),
          // Anchored to the bottom; at very large text sizes the top (artwork) is what gets cut off.
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            reverse: true,
            child: Padding(
              padding: const EdgeInsets.all(KairoSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: KairoSpacing.sm,
                    runSpacing: KairoSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: KairoColors.accent, borderRadius: BorderRadius.circular(10)),
                        child: const Text(
                          'TRENDING',
                          style: TextStyle(
                            color: KairoColors.background,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (anime.score != null) ScoreLabel(score: anime.score!),
                      if (anime.nextAiring != null)
                        Text(
                          anime.nextAiring!.label(),
                          style: const TextStyle(fontSize: 12, color: KairoColors.success, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  const SizedBox(height: KairoSpacing.sm),
                  Text(
                    anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.15),
                  ),
                  const SizedBox(height: KairoSpacing.xs),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFD9D6E8)),
                  ),
                  const SizedBox(height: KairoSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: entry == null
                              ? () {
                                  ref.read(watchlistProvider.notifier).setStatus(anime, ListStatus.planned);
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(SnackBar(content: Text('Added ${anime.title} to Planned')));
                                }
                              : () => context.push(Routes.anime(anime.id)),
                          icon: Icon(entry == null ? Icons.add_rounded : Icons.bookmark_rounded),
                          label: Text(entry == null ? 'Add to list' : entry.status.label),
                        ),
                      ),
                      const SizedBox(width: KairoSpacing.sm),
                      OutlinedButton(
                        onPressed: () => context.push(Routes.anime(anime.id)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: KairoColors.background.withValues(alpha: 0.35),
                        ),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry});

  final WatchEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anime = entry.anime;
    final total = anime.episodes;
    final progress = total == null || total == 0 ? 0.0 : entry.watched / total;
    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: BorderRadius.circular(KairoRadii.panel),
        onTap: () => context.push(Routes.anime(anime.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 124,
              child: CoverArt(
                anime: anime,
                banner: true,
                radius: KairoRadii.panel,
                child: Stack(
                  children: [
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Tooltip(
                        message: 'Mark episode ${entry.watched + 1} watched',
                        child: Material(
                          color: KairoColors.background.withValues(alpha: 0.7),
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: total != null && entry.watched >= total
                                ? null
                                : () => ref.read(watchlistProvider.notifier).markNextWatched(anime),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Text('+1 ep', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: KairoColors.accent,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KairoSpacing.sm),
            Text(
              anime.shortTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              'Ep ${entry.watched} / ${total ?? '?'}',
              style: const TextStyle(
                fontSize: 12,
                color: KairoColors.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (anime.nextAiring != null)
              Text(anime.nextAiring!.label(), style: const TextStyle(fontSize: 12, color: KairoColors.success)),
          ],
        ),
      ),
    );
  }
}

/// The hero card's height: artwork space plus room for its text and buttons at the user's font size.
double _heroHeight(BuildContext context) => 150 + MediaQuery.textScalerOf(context).scale(170);

/// An episode stopped part-way; tapping it resumes playback.
class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.progress, required this.file});

  final PlaybackProgress progress;
  final LibraryFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anime = ref.watch(animeProvider(progress.animeId)) ?? file.anime!;
    final minutesLeft = (progress.remaining.inSeconds / 60).ceil();
    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: BorderRadius.circular(KairoRadii.panel),
        onTap: () => playEpisode(context, ref, anime.id, progress.episode),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 124,
              child: CoverArt(
                anime: anime,
                banner: true,
                radius: KairoRadii.panel,
                child: Stack(
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: KairoColors.background.withValues(alpha: 0.6),
                        child: const Icon(Icons.play_arrow_rounded, color: KairoColors.text),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: 4,
                        color: KairoColors.accent,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: KairoSpacing.sm),
            Text(
              anime.shortTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              'Ep ${progress.episode} · $minutesLeft min left',
              style: const TextStyle(fontSize: 12, color: KairoColors.info),
            ),
          ],
        ),
      ),
    );
  }
}
