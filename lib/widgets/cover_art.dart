import 'package:flutter/material.dart';

import '../data/models.dart';

/// Placeholder cover drawn from the anime's palette. Real AniList artwork replaces it in step 4.
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.anime, this.radius = 12, this.child});

  final Anime anime;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${anime.title} cover',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: anime.palette,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -18,
                bottom: -18,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                  ),
                ),
              ),
              ?child,
            ],
          ),
        ),
      ),
    );
  }
}
