import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/watch_links.dart';
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

/// Asks for a link to watch an episode: a page on a streaming site (Crunchyroll, Bilibili, YouTube…,
/// opened in the built-in browser) or a direct video/stream URL (played in Kairo's player).
Future<({String url, String label, bool direct})?> showWatchLinkDialog(BuildContext context, {required String subtitle}) {
  final url = TextEditingController();
  final label = TextEditingController();
  String? error;
  return showDialog<({String url, String label, bool direct})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final parsed = parseWatchLink(url.text);
        final direct = parsed != null && isDirectMediaLink(parsed.toString());
        final service = parsed == null ? null : serviceFor(parsed.toString());
        return AlertDialog(
          backgroundColor: KairoColors.surface,
          title: const Text('Add a watch link'),
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
                  onChanged: (_) => setState(() => error = null),
                  decoration: InputDecoration(
                    labelText: 'Paste a link',
                    hintText: 'https://www.crunchyroll.com/watch/…',
                    errorText: error,
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: () async {
                        final clip = await Clipboard.getData(Clipboard.kTextPlain);
                        if (clip?.text != null) setState(() => url.text = clip!.text!);
                      },
                    ),
                  ),
                ),
                if (parsed != null) ...[
                  const SizedBox(height: KairoSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        direct ? Icons.play_circle_outline_rounded : Icons.public_rounded,
                        size: 16,
                        color: service?.color ?? KairoColors.primarySoft,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          direct
                              ? 'Direct video: plays in Kairo\'s player'
                              : service?.blocksInAppPlayback == true
                                  ? '${service!.name}: opens in the ${service.name} app'
                                  : '${linkLabel(parsed.toString())}: opens inside Kairo',
                          style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: KairoSpacing.sm),
                TextField(controller: label, decoration: const InputDecoration(labelText: 'Name (optional)')),
                const SizedBox(height: KairoSpacing.md),
                const Text(
                  'Works with Crunchyroll, Bilibili, YouTube, HIDIVE and other sites, '
                  'or a direct MP4/MKV/HLS link from your own server.',
                  style: TextStyle(color: KairoColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (parsed == null) {
                  setState(() => error = 'That doesn\'t look like a link');
                  return;
                }
                Navigator.pop(context, (url: parsed.toString(), label: label.text.trim(), direct: direct));
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}

/// Asks for a link and saves it for [episode] of [anime] (0 = the show's own page).
Future<void> addWatchLinkFor(BuildContext context, WidgetRef ref, Anime anime, int episode) async {
  final link = await showWatchLinkDialog(
    context,
    subtitle: episode == 0 ? '${anime.title} · whole show' : '${anime.title} · Episode $episode',
  );
  if (link == null) return;
  final library = ref.read(libraryProvider.notifier);
  if (link.direct) {
    library.addStream(anime: anime, episode: episode == 0 ? 1 : episode, url: link.url, label: link.label);
  } else {
    library.addWatchLink(anime: anime, episode: episode, url: link.url, label: link.label);
  }
}
