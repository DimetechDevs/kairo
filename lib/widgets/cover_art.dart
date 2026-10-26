import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';

/// AniList artwork, with a gradient in the title's own colour while it loads or when there's none.
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.anime, this.radius = 12, this.banner = false, this.child});

  final Anime anime;
  final double radius;

  /// Prefer the wide banner image (falls back to the cover).
  final bool banner;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final url = banner ? (anime.bannerUrl ?? anime.coverUrl) : anime.coverUrl;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: anime.palette),
      ),
    );

    return Semantics(
      label: '${anime.title} cover',
      image: true,
      // Squircle-style corners, smoother than a plain rounded rectangle.
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            placeholder,
            if (url != null)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 250),
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
            ?child,
          ],
        ),
      ),
    );
  }
}
