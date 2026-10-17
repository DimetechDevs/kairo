import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/anilist.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/poster_card.dart';

enum DiscoverSort {
  trending('Trending', BrowseSort.trending),
  season('This season', BrowseSort.popular),
  popular('Popular', BrowseSort.popular),
  topRated('Top rated', BrowseSort.topRated);

  const DiscoverSort(this.label, this.apiSort);
  final String label;
  final BrowseSort apiSort;
}

/// Lets other tabs open Discover on a given list ("See all" on Home).
class DiscoverRequest extends Notifier<DiscoverSort?> {
  @override
  DiscoverSort? build() => null;

  void open(DiscoverSort sort) => state = sort;
  void clear() => state = null;
}

final discoverRequestProvider = NotifierProvider<DiscoverRequest, DiscoverSort?>(DiscoverRequest.new);

const _formats = {
  'TV': 'TV',
  'MOVIE': 'Movie',
  'ONA': 'ONA',
  'OVA': 'OVA',
  'SPECIAL': 'Special',
  'TV_SHORT': 'TV Short',
};
const _statuses = {'RELEASING': 'Airing', 'FINISHED': 'Finished', 'NOT_YET_RELEASED': 'Upcoming'};

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  DiscoverSort _sort = DiscoverSort.trending;
  String? _genre;
  String? _format;
  String? _status;

  final _items = <Anime>[];
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  /// Bumped on every new search so late answers from an older one are ignored.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
    final requested = ref.read(discoverRequestProvider);
    if (requested != null) {
      _sort = requested;
      Future.microtask(() => ref.read(discoverRequestProvider.notifier).clear());
    }
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasNext = true;
      _error = null;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    return _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final generation = _generation;
    final season = _sort == DiscoverSort.season ? seasonOf(DateTime.now()) : null;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(aniListProvider)
          .browse(
            page: _page + 1,
            sort: _sort.apiSort,
            search: _search.text,
            genre: _genre,
            format: _format,
            status: _status,
            season: season?.season,
            seasonYear: season?.year,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        // AniList can repeat a title across pages when rankings shift; skip duplicates.
        final seen = _items.map((a) => a.id).toSet();
        _items.addAll(page.items.where((a) => seen.add(a.id)));
        _page = page.page;
        _hasNext = page.hasNext;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    setState(() {}); // Shows or hides the clear button.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _reload);
  }

  int get _activeFilters => (_format == null ? 0 : 1) + (_status == null ? 0 : 1);

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<(String?, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(format: _format, status: _status),
    );
    if (result == null) return;
    _format = result.$1;
    _status = result.$2;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(discoverRequestProvider, (_, next) {
      if (next == null) return;
      ref.read(discoverRequestProvider.notifier).clear();
      if (next != _sort) {
        _sort = next;
        _reload();
      }
    });

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
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      _debounce?.cancel();
                      _reload();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search anime',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                _onSearchChanged('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KairoRadii.pill),
                        borderSide: const BorderSide(color: KairoColors.primarySoft),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KairoSpacing.sm),
                Badge(
                  isLabelVisible: _activeFilters > 0,
                  label: Text('$_activeFilters'),
                  backgroundColor: KairoColors.accent,
                  child: IconButton.outlined(
                    tooltip: 'Filters',
                    onPressed: _openFilters,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KairoSpacing.sm),
          _SortTabs(
            selected: _sort,
            onSelected: (s) {
              if (s == _sort) return;
              _sort = s;
              _reload();
            },
          ),
          const SizedBox(height: KairoSpacing.sm),
          HorizontalStrip(
            spacing: KairoSpacing.sm,
            children: [
              for (final genre in [null, ...aniListGenres])
                FilterPill(
                  label: genre ?? 'All',
                  selected: genre == _genre,
                  selectedColor: KairoColors.accent,
                  selectedTextColor: KairoColors.background,
                  onTap: () {
                    if (genre == _genre) return;
                    _genre = genre;
                    _reload();
                  },
                ),
            ],
          ),
          const SizedBox(height: KairoSpacing.md),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _results() {
    if (_items.isEmpty && _error != null) return ErrorState(error: _error!, onRetry: _reload);
    if (_items.isEmpty && !_loading && !_hasNext) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Try another title, genre or filter.',
      );
    }

    // Each cell is a 2:3 poster plus two title lines and a meta line, sized for the user's font size.
    final width = MediaQuery.sizeOf(context).width;
    final scaler = MediaQuery.textScalerOf(context);
    final columns = width / scaler.scale(1) < 300 ? 2 : 3;
    final cellWidth = (width - 2 * KairoSpacing.gutter - (columns - 1) * KairoSpacing.md) / columns;
    final grid = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: KairoSpacing.lg,
      crossAxisSpacing: KairoSpacing.md,
      // Poster + 6px gap + measured text, with 2px of slack for rounding.
      mainAxisExtent: cellWidth * 1.5 + 6 + PosterCard.textHeight(context) + 2,
    );
    const padding = EdgeInsets.symmetric(horizontal: KairoSpacing.gutter);

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: _items.isEmpty
                ? SliverGrid.builder(gridDelegate: grid, itemCount: 9, itemBuilder: (_, _) => const PosterSkeleton())
                : SliverGrid.builder(
                    gridDelegate: grid,
                    itemCount: _items.length,
                    itemBuilder: (_, i) => PosterCard(anime: _items[i], showMeta: true),
                  ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KairoSpacing.xl),
              child: Center(
                child: switch ((_items.isNotEmpty, _loading, _error)) {
                  (true, true, _) => const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  (true, false, final Object _) => TextButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Couldn't load more · Try again"),
                  ),
                  (true, false, null) when !_hasNext => const Text(
                    "That's everything",
                    style: TextStyle(fontSize: 12, color: KairoColors.textMuted),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text tabs for the sort order, with a short bar under the selected one.
class _SortTabs extends StatelessWidget {
  const _SortTabs({required this.selected, required this.onSelected});

  final DiscoverSort selected;
  final ValueChanged<DiscoverSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter - 8),
      child: Row(
        children: [
          for (final s in DiscoverSort.values)
            Semantics(
              selected: s == selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(s),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Column(
                    children: [
                      Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: s == selected ? FontWeight.w700 : FontWeight.w500,
                          color: s == selected ? KairoColors.text : KairoColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: s == selected ? 20 : 0,
                        height: 3,
                        decoration: BoxDecoration(color: KairoColors.primary, borderRadius: BorderRadius.circular(2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.format, required this.status});

  final String? format;
  final String? status;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _format = widget.format;
  late String? _status = widget.status;

  Widget _group(String title, Map<String, String> options, String? value, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: KairoSpacing.sm),
        Wrap(
          spacing: KairoSpacing.sm,
          runSpacing: KairoSpacing.sm,
          children: [
            FilterPill(label: 'Any', selected: value == null, onTap: () => onChanged(null)),
            for (final o in options.entries)
              FilterPill(label: o.value, selected: value == o.key, onTap: () => onChanged(o.key)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 0, KairoSpacing.gutter, KairoSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _group('Format', _formats, _format, (v) => setState(() => _format = v)),
              const SizedBox(height: KairoSpacing.xl),
              _group('Status', _statuses, _status, (v) => setState(() => _status = v)),
              const SizedBox(height: KairoSpacing.xxl),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, (null, null)),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Reset'),
                  ),
                  const SizedBox(width: KairoSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, (_format, _status)),
                      child: const Text('Show results'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
