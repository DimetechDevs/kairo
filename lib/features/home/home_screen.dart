import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/poster_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    final progress = ref.watch(progressProvider);
    final featured = catalogue.first;
    final featuredProgress = progress.where((p) => p.animeId == featured.id).firstOrNull;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: KairoSpacing.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, KairoSpacing.lg, KairoSpacing.md, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Kai'),
                      TextSpan(text: 'ro', style: TextStyle(color: KairoColors.primary)),
                    ]),
                    style: KairoTheme.display(context),
                    semanticsLabel: 'Kairo',
                  ),
                ),
                IconButton(
                  tooltip: 'Search',
                  onPressed: () => StatefulNavigationShell.of(context).goBranch(1),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  tooltip: 'Profile',
                  onPressed: () => StatefulNavigationShell.of(context).goBranch(4),
                  icon: const CircleAvatar(
                    radius: 16,
                    backgroundColor: KairoColors.primary,
                    child: Text('G', style: TextStyle(color: KairoColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KairoSpacing.lg),
          _FeaturedHero(anime: featured, progress: featuredProgress),
          const SizedBox(height: KairoSpacing.xxl),
          if (progress.isNotEmpty) ...[
            const SectionHeader('Continue watching'),
            const SizedBox(height: KairoSpacing.md),
            SizedBox(
              // Card art plus two text lines, grown with the system font size.
              height: 132 + MediaQuery.textScalerOf(context).scale(56),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                itemCount: progress.length,
                separatorBuilder: (_, _) => const SizedBox(width: KairoSpacing.md),
                itemBuilder: (_, i) => _ContinueCard(
                  progress: progress[i],
                  anime: ref.watch(animeProvider(progress[i].animeId)),
                ),
              ),
            ),
            const SizedBox(height: KairoSpacing.xl),
          ],
          PosterRow(
            title: 'Trending now',
            items: catalogue.skip(1).take(5).toList(),
            onSeeAll: () => StatefulNavigationShell.of(context).goBranch(1),
          ),
          const SizedBox(height: KairoSpacing.lg),
          PosterRow(
            title: 'Popular this season',
            items: catalogue.reversed.take(5).toList(),
            onSeeAll: () => StatefulNavigationShell.of(context).goBranch(1),
          ),
        ],
      ),
    );
  }
}

class _FeaturedHero extends StatelessWidget {
  const _FeaturedHero({required this.anime, required this.progress});

  final Anime anime;
  final PlaybackProgress? progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
      child: SizedBox(
        height: 300,
        child: CoverArt(
          anime: anime,
          radius: KairoRadii.hero,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, KairoColors.background],
                stops: [0.25, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(KairoSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: KairoColors.accent, borderRadius: BorderRadius.circular(10)),
                    child: const Text(
                      'FEATURED',
                      style: TextStyle(color: KairoColors.background, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: KairoSpacing.sm),
                  Text(anime.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.15)),
                  const SizedBox(height: KairoSpacing.xs),
                  Text(
                    '${anime.year} · ${anime.format} · ${anime.episodes} episodes · ${anime.genres.last}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFFD9D6E8)),
                  ),
                  const SizedBox(height: KairoSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: progress != null
                            ? FilledButton.icon(
                                onPressed: () => context.push(Routes.player(anime.id, progress!.episode)),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text('Play Ep ${progress!.episode}'),
                              )
                            : FilledButton(
                                onPressed: () => context.push(Routes.anime(anime.id)),
                                child: const Text('Add to list'),
                              ),
                      ),
                      const SizedBox(width: KairoSpacing.sm),
                      OutlinedButton(
                        onPressed: () => context.push(Routes.anime(anime.id)),
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

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.progress, required this.anime});

  final PlaybackProgress progress;
  final Anime anime;

  @override
  Widget build(BuildContext context) {
    final minutesLeft = (progress.remaining.inSeconds / 60).ceil();
    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: BorderRadius.circular(KairoRadii.panel),
        onTap: () => context.push(Routes.player(anime.id, progress.episode)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 124,
              child: CoverArt(
                anime: anime,
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
            Text(anime.shortTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(
              'Ep ${progress.episode} · $minutesLeft min left',
              style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
