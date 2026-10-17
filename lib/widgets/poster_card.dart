import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';
import 'cover_art.dart';

/// 2:3 poster with the title underneath. Opens the details page.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.anime, this.width, this.showMeta = false});

  final Anime anime;
  final double? width;
  final bool showMeta;

  static const titleStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3);
  static const metaStyle = TextStyle(fontSize: 11, color: KairoColors.textSecondary);

  /// Height of the text under the poster (two title lines, plus the meta line) as it will
  /// actually render: measured with the real font and the user's text size, not estimated.
  static double textHeight(BuildContext context, {bool withMeta = true}) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(TextStyle style, int lines) {
      final painter = TextPainter(
        text: TextSpan(text: List.filled(lines, 'Ag').join('\n'), style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return measure(titleStyle, 2) + (withMeta ? measure(metaStyle, 1) : 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(KairoRadii.card),
        onTap: () => context.push(Routes.anime(anime.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: CoverArt(
                anime: anime,
                child: Stack(
                  children: [
                    // Darkens the bottom so the badges stay readable on bright covers.
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x99000000)],
                            stops: [0.6, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _Badge(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (anime.isAiring) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(color: KairoColors.success, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(anime.formatLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    if (anime.score != null)
                      Positioned(right: 6, bottom: 6, child: _Badge(child: ScoreLabel(score: anime.score!, size: 11))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              anime.shortTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            if (showMeta)
              Text(
                [if (anime.year != null) '${anime.year}', anime.episodesLabel].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle,
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KairoColors.background.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

/// A horizontal row of posters with a header.
class PosterRow extends StatelessWidget {
  const PosterRow({super.key, required this.title, required this.items, this.onSeeAll});

  final String title;
  final List<Anime> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, actionLabel: onSeeAll == null ? null : 'See all', onAction: onSeeAll),
        const SizedBox(height: KairoSpacing.xs),
        HorizontalStrip(children: [for (final a in items) PosterCard(anime: a, width: 112)]),
      ],
    );
  }
}

/// Placeholder for a [PosterRow] while it loads.
class PosterRowSkeleton extends StatelessWidget {
  const PosterRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: KairoSpacing.gutter, vertical: 14),
          child: Skeleton(width: 160, height: 18),
        ),
        HorizontalStrip(
          physics: NeverScrollableScrollPhysics(),
          children: [PosterSkeleton(width: 112), PosterSkeleton(width: 112), PosterSkeleton(width: 112), PosterSkeleton(width: 112)],
        ),
      ],
    );
  }
}

class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({super.key, this.width});

  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 2 / 3, child: Skeleton(radius: KairoRadii.card)),
          SizedBox(height: 8),
          Skeleton(height: 12),
          SizedBox(height: 6),
          FractionallySizedBox(widthFactor: 0.6, child: Skeleton(height: 12)),
        ],
      ),
    );
  }
}
