import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'common.dart';
import 'cover_art.dart';

/// Search AniList for a show and choose an episode number. Returns null if cancelled.
Future<(Anime, int)?> showMatchSheet(
  BuildContext context, {
  String title = 'Which show is this?',
  String initialQuery = '',
  Anime? initialAnime,
  int initialEpisode = 1,
}) {
  return showModalBottomSheet<(Anime, int)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MatchSheet(title: title, initialQuery: initialQuery, initialAnime: initialAnime, initialEpisode: initialEpisode),
  );
}

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet({required this.title, required this.initialQuery, required this.initialAnime, required this.initialEpisode});

  final String title;
  final String initialQuery;
  final Anime? initialAnime;
  final int initialEpisode;

  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  late final _query = TextEditingController(text: widget.initialQuery);
  late final _episode = TextEditingController(text: '${widget.initialEpisode}');
  Timer? _debounce;
  List<Anime> _results = const [];
  bool _loading = false;
  Object? _error;
  late Anime? _selected = widget.initialAnime;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _episode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(aniListProvider).browse(search: q, perPage: 12);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.items;
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

  @override
  Widget build(BuildContext context) {
    final episode = int.tryParse(_episode.text.trim());
    final selected = _selected;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                child: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: KairoSpacing.md),
              if (selected == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                  child: TextField(
                    controller: _query,
                    autofocus: widget.initialQuery.isEmpty,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), _search);
                    },
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Search AniList',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: KairoColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(KairoRadii.pill), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(height: KairoSpacing.sm),
                Flexible(
                  child: _loading
                      ? const Padding(padding: EdgeInsets.all(KairoSpacing.xl), child: Center(child: CircularProgressIndicator()))
                      : _error != null
                          ? ErrorState(error: _error!, onRetry: _search)
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final a in _results)
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter, vertical: 2),
                                    leading: SizedBox(width: 40, height: 58, child: CoverArt(anime: a, radius: 6)),
                                    title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      [if (a.year != null) '${a.year}', a.formatLabel, a.episodesLabel].join(' · '),
                                      style: const TextStyle(color: KairoColors.textSecondary),
                                    ),
                                    onTap: () => setState(() => _selected = a),
                                  ),
                              ],
                            ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                  child: Row(
                    children: [
                      SizedBox(width: 48, height: 70, child: CoverArt(anime: selected, radius: 8)),
                      const SizedBox(width: KairoSpacing.md),
                      Expanded(
                        child: Text(selected.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      TextButton(onPressed: () => setState(() => _selected = null), child: const Text('Change')),
                    ],
                  ),
                ),
                const SizedBox(height: KairoSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Episode', style: TextStyle(fontSize: 15))),
                      IconButton.outlined(
                        tooltip: 'Previous episode',
                        onPressed: (episode ?? 1) > 1 ? () => setState(() => _episode.text = '${episode! - 1}') : null,
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _episode,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(border: InputBorder.none),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Next episode',
                        onPressed: () => setState(() => _episode.text = '${(episode ?? 0) + 1}'),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KairoSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
                  child: FilledButton(
                    onPressed: episode == null || episode < 1 ? null : () => Navigator.pop(context, (selected, episode)),
                    child: const Text('Confirm'),
                  ),
                ),
                const SizedBox(height: KairoSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a stream URL the user controls (their own server, a direct HLS/MP4 link).
Future<({String url, String label})?> showStreamUrlDialog(BuildContext context, {required String subtitle}) {
  final url = TextEditingController();
  final label = TextEditingController();
  String? error;
  return showDialog<({String url, String label})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: KairoColors.surface,
        title: const Text('Add a stream URL'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: const TextStyle(color: KairoColors.textSecondary, fontSize: 13)),
              const SizedBox(height: KairoSpacing.md),
              TextField(
                controller: url,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'https://…', errorText: error),
              ),
              const SizedBox(height: KairoSpacing.sm),
              TextField(controller: label, decoration: const InputDecoration(labelText: 'Name (optional)')),
              const SizedBox(height: KairoSpacing.md),
              const Text(
                'Use links from your own media server (Jellyfin, Plex, a NAS) or another source you have the rights to. '
                'Direct MP4, MKV and HLS (.m3u8) links work.',
                style: TextStyle(color: KairoColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = Uri.tryParse(url.text.trim());
              if (parsed == null || !(parsed.scheme == 'http' || parsed.scheme == 'https') || parsed.host.isEmpty) {
                setState(() => error = 'Enter a full http(s) link');
                return;
              }
              Navigator.pop(context, (url: url.text.trim(), label: label.text.trim()));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
