import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'cover_art.dart';

/// 2:3 poster with the title underneath. Opens the details page.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.anime, this.width, this.showMeta = false});

  final Anime anime;
  final double? width;
  final bool showMeta;

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
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KairoColors.background.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(anime.format, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              anime.shortTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3),
            ),
            if (showMeta)
              Text(
                '${anime.year} · ${anime.episodes} eps',
                style: const TextStyle(fontSize: 11, color: KairoColors.textSecondary),
              ),
          ],
        ),
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(foregroundColor: KairoColors.info),
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        const SizedBox(height: KairoSpacing.sm),
        SizedBox(
          // 112px-wide 2:3 poster plus two title lines, grown with the system font size.
          height: 174 + MediaQuery.textScalerOf(context).scale(44),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: KairoSpacing.md),
            itemBuilder: (_, i) => PosterCard(anime: items[i], width: 112),
          ),
        ),
      ],
    );
  }
}
