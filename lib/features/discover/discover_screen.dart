import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/poster_card.dart';

enum DiscoverSort { trending, season, popular }

extension on DiscoverSort {
  String get label => switch (this) {
        DiscoverSort.trending => 'Trending',
        DiscoverSort.season => 'This season',
        DiscoverSort.popular => 'Popular',
      };
}

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  static const _genres = ['All', 'Action', 'Fantasy', 'Comedy', 'Drama', 'Sci-Fi', 'Sports', 'Mystery'];

  final _search = TextEditingController();
  DiscoverSort _sort = DiscoverSort.trending;
  String _genre = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Anime> _results(List<Anime> catalogue) {
    // Mock ordering per tab; AniList provides real sort orders in step 4.
    final ordered = switch (_sort) {
      DiscoverSort.trending => catalogue.skip(1).followedBy(catalogue.take(1)).toList(),
      DiscoverSort.season => [...catalogue]..sort((a, b) => b.year.compareTo(a.year)),
      DiscoverSort.popular => catalogue.reversed.toList(),
    };
    final query = _search.text.trim().toLowerCase();
    return ordered.where((a) {
      final genreOk = _genre == 'All' || a.genres.contains(_genre);
      final queryOk = query.isEmpty ||
          a.title.toLowerCase().contains(query) ||
          (a.nativeTitle?.toLowerCase().contains(query) ?? false);
      return genreOk && queryOk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results(ref.watch(catalogueProvider));

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenTitle('Discover'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search anime',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: KairoColors.surface,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KairoRadii.pill),
                        borderSide: const BorderSide(color: KairoColors.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KairoRadii.pill),
                        borderSide: const BorderSide(color: KairoColors.outline),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KairoSpacing.sm),
                IconButton.outlined(
                  tooltip: 'Filters',
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Format, year and status filters arrive with AniList.')),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: KairoSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
            child: SegmentedButton<DiscoverSort>(
              showSelectedIcon: false,
              segments: [for (final s in DiscoverSort.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {_sort},
              onSelectionChanged: (s) => setState(() => _sort = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: KairoColors.primary,
                selectedForegroundColor: KairoColors.text,
                side: const BorderSide(color: KairoColors.outline),
              ),
            ),
          ),
          const SizedBox(height: KairoSpacing.md),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
              itemCount: _genres.length,
              separatorBuilder: (_, _) => const SizedBox(width: KairoSpacing.sm),
              itemBuilder: (_, i) => FilterPill(
                label: _genres[i],
                selected: _genres[i] == _genre,
                selectedColor: KairoColors.accent,
                selectedTextColor: KairoColors.background,
                onTap: () => setState(() => _genre = _genres[i]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, KairoSpacing.md, KairoSpacing.gutter, KairoSpacing.sm),
            child: Text(
              '${results.length} titles',
              style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message: 'Try another title or genre.',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 0, KairoSpacing.gutter, KairoSpacing.xxl),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: KairoSpacing.lg,
                      crossAxisSpacing: KairoSpacing.md,
                      childAspectRatio: 0.48,
                    ),
                    itemCount: results.length,
                    itemBuilder: (_, i) => PosterCard(anime: results[i], showMeta: true),
                  ),
          ),
        ],
      ),
    );
  }
}
