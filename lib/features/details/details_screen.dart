import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/watch_links.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/match_sheet.dart';
import '../../widgets/poster_card.dart';
import '../watch/web_watch_screen.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key, required this.animeId});

  final int animeId;

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  static const _collapsedEpisodes = 12;

  bool _expanded = false;
  bool _allEpisodes = false;

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(animeDetailsProvider(widget.animeId));
    final entry = ref.watch(watchlistProvider)[widget.animeId];

    // Keep the saved copy in the watchlist up to date (new episodes, artwork).
    ref.listen(animeDetailsProvider(widget.animeId), (_, next) {
      if (next.value case final anime?) ref.read(watchlistProvider.notifier).refreshSnapshot(anime);
    });

    final anime = details.value ?? entry?.anime;
    if (anime == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: details.hasError
            ? ErrorState(error: details.error!, onRetry: () => ref.invalidate(animeDetailsProvider(widget.animeId)))
            : const _DetailsSkeleton(),
      );
    }

    final watched = entry?.watched ?? 0;
    final episodeCount = anime.episodes ?? anime.airedEpisodes;
    final shownEpisodes = _allEpisodes ? episodeCount : episodeCount.clamp(0, _collapsedEpisodes);
    final accent = anime.accent;

    // What the main button plays: an episode in progress, else the next one in the library.
    final files = {
      for (final f in ref.watch(libraryProvider))
        if (f.playable && f.animeId == anime.id) f.episode!: f,
    };
    final progress = ref.watch(progressProvider);
    final resumeEpisode = ref.watch(resumeListProvider).where((r) => r.$1.animeId == anime.id).firstOrNull?.$1.episode;
    final playEpisode = resumeEpisode ?? (files.keys.where((e) => e > watched).toList()..sort()).firstOrNull;

    // Watch links the user saved: per episode, and one for the whole show (episode 0).
    final links = ref.read(libraryProvider.notifier).watchLinksFor(anime.id);
    final episodeLinks = {
      for (final l in links)
        if (l.episode! > 0) l.episode!: l,
    };
    final showLink = links.where((l) => l.episode == 0).firstOrNull;
    final nextEpisode = watched + 1;
    final nextLink = episodeLinks[nextEpisode] ?? showLink;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            backgroundColor: KairoColors.background,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton.filledTonal(
                tooltip: 'Back',
                style: IconButton.styleFrom(backgroundColor: KairoColors.background.withValues(alpha: 0.6)),
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: CoverArt(
                anime: anime,
                banner: true,
                radius: 0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Colors.transparent, KairoColors.background],
                      stops: [0, 0.4, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 0, KairoSpacing.gutter, 0),
            sliver: SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 104,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(KairoRadii.panel),
                        boxShadow: [
                          BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: CoverArt(anime: anime, radius: KairoRadii.panel),
                    ),
                    const SizedBox(width: KairoSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            anime.title,
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.2),
                          ),
                          if (anime.nativeTitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              anime.nativeTitle!,
                              style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
                            ),
                          ],
                          if (anime.studios.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              anime.studios.join(', '),
                              style: TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.lg),
                _InfoStrip(anime: anime),
                if (anime.nextAiring != null) ...[
                  const SizedBox(height: KairoSpacing.md),
                  _Banner(
                    icon: Icons.schedule_rounded,
                    color: KairoColors.success,
                    text: '${anime.nextAiring!.label()} · ${_weekday(anime.nextAiring!.at)}',
                  ),
                ],
                const SizedBox(height: KairoSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: playEpisode == null && nextLink != null
                          ? FilledButton.icon(
                              onPressed: () =>
                                  openWatchLink(context, ref, nextLink.uri, animeId: anime.id, episode: nextEpisode),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                'Watch Ep $nextEpisode on ${linkLabel(nextLink.uri)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : playEpisode != null
                          ? FilledButton.icon(
                              onPressed: () => context.push(Routes.player(anime.id, playEpisode)),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                resumeEpisode != null ? 'Resume Ep $playEpisode' : 'Play Ep $playEpisode',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : entry == null
                          ? FilledButton.icon(
                              onPressed: () =>
                                  ref.read(watchlistProvider.notifier).setStatus(anime, ListStatus.planned),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add to list'),
                            )
                          : FilledButton.icon(
                              onPressed: anime.episodes != null && watched >= anime.episodes!
                                  ? null
                                  : () => ref.read(watchlistProvider.notifier).setWatched(anime, watched + 1),
                              icon: const Icon(Icons.check_rounded),
                              label: Text(
                                anime.episodes != null && watched >= anime.episodes!
                                    ? 'All watched'
                                    : 'Watched Ep ${watched + 1}',
                              ),
                            ),
                    ),
                    const SizedBox(width: KairoSpacing.sm),
                    _StatusButton(
                      status: entry?.status,
                      onSelected: (s) => ref.read(watchlistProvider.notifier).setStatus(anime, s),
                      onRemove: entry == null ? null : () => ref.read(watchlistProvider.notifier).remove(anime.id),
                    ),
                  ],
                ),
                if (entry != null && episodeCount > 0) ...[
                  const SizedBox(height: KairoSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: ProgressLine(value: watched / episodeCount, color: accent),
                      ),
                      const SizedBox(width: KairoSpacing.md),
                      Text(
                        '$watched / ${anime.episodes ?? '?'}',
                        style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: KairoSpacing.lg),
                Wrap(
                  spacing: KairoSpacing.sm,
                  runSpacing: KairoSpacing.sm,
                  children: [for (final g in anime.genres) TagChip(g)],
                ),
                const SizedBox(height: KairoSpacing.lg),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: Text(
                    anime.synopsis,
                    maxLines: _expanded ? null : 4,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.65, color: Color(0xFFD9D6E8)),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(foregroundColor: KairoColors.info, padding: EdgeInsets.zero),
                    child: Text(_expanded ? 'Show less' : 'Read more'),
                  ),
                ),
                ...[
                  const SizedBox(height: KairoSpacing.sm),
                  _WhereToWatch(
                    links: anime.streamingLinks,
                    saved: links,
                    onOpen: (url, {episode}) => openWatchLink(context, ref, url, animeId: anime.id, episode: episode),
                    onAdd: () => addWatchLinkFor(context, ref, anime, 0),
                    onRemove: (id) => ref.read(libraryProvider.notifier).remove(id),
                  ),
                  const SizedBox(height: KairoSpacing.xl),
                ],
                if (episodeCount > 0) ...[
                  const SizedBox(height: KairoSpacing.sm),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Episodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      Flexible(
                        child: Text(
                          anime.isAiring && anime.episodes != null
                              ? '${anime.airedEpisodes} of ${anime.episodes} aired'
                              : '$episodeCount episodes',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KairoSpacing.sm),
                  for (var ep = 1; ep <= shownEpisodes; ep++)
                    _EpisodeRow(
                      anime: anime,
                      episode: ep,
                      watched: ep <= watched,
                      aired: !anime.isAiring || ep <= anime.airedEpisodes,
                      onToggle: () =>
                          ref.read(watchlistProvider.notifier).setWatched(anime, ep <= watched ? ep - 1 : ep),
                      file: files[ep],
                      webLink: episodeLinks[ep],
                      streaming: anime.streamingEpisode(ep),
                      progress: progress[(anime.id, ep)],
                      onAddFile: () => _addFile(anime, ep),
                      onAddStream: () => _addStream(anime, ep),
                      onOpenOfficial: (url) => openWatchLink(context, ref, url, animeId: anime.id, episode: ep),
                    ),
                  if (episodeCount > _collapsedEpisodes)
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _allEpisodes = !_allEpisodes),
                        style: TextButton.styleFrom(foregroundColor: KairoColors.info),
                        child: Text(_allEpisodes ? 'Show fewer' : 'Show all $episodeCount episodes'),
                      ),
                    ),
                ],
                if (details.isLoading && details.value == null)
                  const Padding(
                    padding: EdgeInsets.all(KairoSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          if (anime.recommendations.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: KairoSpacing.lg),
                child: PosterRow(title: 'You might also like', items: anime.recommendations),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: KairoSpacing.xxl * 2)),
        ],
      ),
    );
  }

  Future<void> _addFile(Anime anime, int episode) async {
    final doc = await ref.read(documentsProvider).pickVideo();
    if (doc == null) return;
    ref.read(libraryProvider.notifier).addFileFor(doc, anime, episode);
  }

  Future<void> _addStream(Anime anime, int episode) async {
    await addWatchLinkFor(context, ref, anime, episode);
  }

  static String _weekday(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final local = t.toLocal();
    return '${days[local.weekday - 1]} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Score, episodes, format and season in one row.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context) {
    final season = anime.season == null ? null : '${anime.season![0]}${anime.season!.substring(1).toLowerCase()}';
    final cells = <(Widget, String)>[
      (
        anime.score == null
            ? const Text('–', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))
            : ScoreLabel(score: anime.score!, size: 15),
        'Score',
      ),
      (
        Text(anime.episodes?.toString() ?? '?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        'Episodes',
      ),
      (Text(anime.formatLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), anime.statusLabel),
      (
        Text(anime.year?.toString() ?? '–', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        season ?? 'Year',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: KairoSpacing.md),
      decoration: BoxDecoration(color: KairoColors.surface, borderRadius: BorderRadius.circular(KairoRadii.panel)),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) Container(width: 1, height: 28, color: KairoColors.outline),
            Expanded(
              child: Column(
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: cells[i].$1),
                  const SizedBox(height: 2),
                  Text(cells[i].$2, style: const TextStyle(fontSize: 11, color: KairoColors.textSecondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(KairoRadii.card),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onSelected, this.onRemove});

  final ListStatus? status;
  final ValueChanged<ListStatus> onSelected;
  final VoidCallback? onRemove;

  Color get _color => switch (status) {
    ListStatus.watching => KairoColors.primarySoft,
    ListStatus.completed => KairoColors.success,
    ListStatus.paused => KairoColors.info,
    ListStatus.dropped => KairoColors.accent,
    ListStatus.planned || null => KairoColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final s in ListStatus.values)
          MenuItemButton(
            onPressed: () => onSelected(s),
            leadingIcon: Icon(
              s == status ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
            ),
            child: Text(s.label),
          ),
        if (onRemove != null) ...[
          const Divider(height: 1),
          MenuItemButton(
            onPressed: onRemove,
            leadingIcon: const Icon(Icons.delete_outline_rounded, size: 18, color: KairoColors.accent),
            child: const Text('Remove from list', style: TextStyle(color: KairoColors.accent)),
          ),
        ],
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: OutlinedButton.styleFrom(
          foregroundColor: _color,
          side: BorderSide(color: _color),
          minimumSize: const Size(0, 48),
        ),
        icon: Icon(status == null ? Icons.bookmark_add_outlined : Icons.bookmark_rounded, size: 18),
        label: Text(status?.label ?? 'Status'),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.anime,
    required this.episode,
    required this.watched,
    required this.aired,
    required this.onToggle,
    required this.onAddFile,
    required this.onAddStream,
    required this.onOpenOfficial,
    this.file,
    this.webLink,
    this.streaming,
    this.progress,
  });

  final Anime anime;
  final int episode;
  final bool watched;
  final bool aired;
  final LibraryFile? file;

  /// A saved link to this episode on a streaming site.
  final LibraryFile? webLink;
  final StreamingEpisode? streaming;
  final PlaybackProgress? progress;
  final VoidCallback onToggle;
  final VoidCallback onAddFile;
  final VoidCallback onAddStream;
  final ValueChanged<String> onOpenOfficial;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final (label, color) = switch ((watched, aired)) {
      _ when file != null && p != null && !p.finished => (
        '${(p.remaining.inSeconds / 60).ceil()} min left',
        KairoColors.info,
      ),
      (true, _) => ('Watched', KairoColors.success),
      _ when file != null => (file!.isStream ? 'Stream ready' : 'In your library', KairoColors.success),
      _ when webLink != null => (
        'Watch on ${linkLabel(webLink!.uri)}',
        serviceFor(webLink!.uri)?.color ?? KairoColors.info,
      ),
      (false, true) => (anime.duration != null ? '${anime.duration} min' : 'Aired', KairoColors.textSecondary),
      (false, false) => ('Not aired yet', KairoColors.textMuted),
    };
    final thumbnail = streaming?.thumbnail;
    final fraction = file != null && p != null ? (p.finished ? 1.0 : p.fraction) : (watched ? 1.0 : 0.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: KairoSpacing.sm),
      child: Material(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: file != null
              ? () => context.push(Routes.player(anime.id, episode))
              : webLink != null
              ? () => onOpenOfficial(webLink!.uri)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(KairoSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 56,
                  child: Opacity(
                    opacity: aired ? 1 : 0.4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (thumbnail != null)
                            CachedNetworkImage(
                              imageUrl: thumbnail,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => CoverArt(anime: anime, banner: true, radius: 0),
                            )
                          else
                            CoverArt(anime: anime, banner: true, radius: 0),
                          ColoredBox(color: Colors.black.withValues(alpha: thumbnail != null ? 0.15 : 0.35)),
                          Center(
                            child: file != null || webLink != null
                                ? const Icon(Icons.play_circle_fill_rounded, size: 28)
                                : thumbnail == null
                                ? Text('$episode', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
                                : null,
                          ),
                          if (fraction > 0)
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: FractionallySizedBox(
                                widthFactor: fraction.clamp(0, 1),
                                child: const SizedBox(height: 3, child: ColoredBox(color: KairoColors.accent)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KairoSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Episode $episode', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (streaming?.name case final name?)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFD9D6E8)),
                        ),
                      const SizedBox(height: 2),
                      Text(label, style: TextStyle(fontSize: 12, color: color)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: watched ? 'Mark episode $episode unwatched' : 'Mark watched up to episode $episode',
                  onPressed: aired ? onToggle : null,
                  icon: Icon(
                    watched ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: watched ? KairoColors.success : KairoColors.textMuted,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Episode options',
                  color: KairoColors.surfaceRaised,
                  icon: const Icon(Icons.more_vert_rounded, color: KairoColors.textSecondary),
                  onSelected: (v) => switch (v) {
                    'file' => onAddFile(),
                    'stream' => onAddStream(),
                    _ => onOpenOfficial(v),
                  },
                  itemBuilder: (_) => [
                    if (streaming != null)
                      PopupMenuItem(
                        value: streaming!.url,
                        child: Text('Watch on ${streaming!.site ?? 'official site'}'),
                      ),
                    PopupMenuItem(value: 'file', child: Text(file == null ? 'Add video file' : 'Replace video file')),
                    const PopupMenuItem(value: 'stream', child: Text('Add watch link')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Official services from AniList plus the links the user saved, with a button to add one.
class _WhereToWatch extends StatelessWidget {
  const _WhereToWatch({
    required this.links,
    required this.saved,
    required this.onOpen,
    required this.onAdd,
    required this.onRemove,
  });

  final List<ExternalLink> links;
  final List<LibraryFile> saved;
  final void Function(String url, {int? episode}) onOpen;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Where to watch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: KairoSpacing.sm),
        Wrap(
          spacing: KairoSpacing.sm,
          runSpacing: KairoSpacing.sm,
          children: [
            for (final l in links)
              ActionChip(
                onPressed: () => onOpen(l.url),
                backgroundColor: KairoColors.surface,
                side: BorderSide(color: (l.color ?? KairoColors.outline).withValues(alpha: 0.7)),
                shape: const StadiumBorder(),
                avatar: Icon(Icons.play_circle_outline_rounded, size: 16, color: l.color ?? KairoColors.primarySoft),
                label: Text(l.language == null ? l.site : '${l.site} · ${l.language}'),
              ),
            for (final s in saved)
              InputChip(
                onPressed: () => onOpen(s.uri, episode: s.episode == 0 ? null : s.episode),
                onDeleted: () => onRemove(s.id),
                deleteButtonTooltipMessage: 'Remove link',
                backgroundColor: KairoColors.surfaceRaised,
                side: BorderSide(color: (serviceFor(s.uri)?.color ?? KairoColors.primarySoft).withValues(alpha: 0.7)),
                shape: const StadiumBorder(),
                avatar: Icon(
                  Icons.bookmark_rounded,
                  size: 16,
                  color: serviceFor(s.uri)?.color ?? KairoColors.primarySoft,
                ),
                label: Text(s.episode == 0 ? s.fileName : '${s.fileName} · Ep ${s.episode}'),
              ),
            ActionChip(
              onPressed: onAdd,
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: KairoColors.outline),
              shape: const StadiumBorder(),
              avatar: const Icon(Icons.add_link_rounded, size: 16, color: KairoColors.info),
              label: const Text('Add a link'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KairoSpacing.gutter),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Skeleton(width: 104, height: 150, radius: KairoRadii.panel),
            SizedBox(width: KairoSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Skeleton(height: 20), SizedBox(height: 8), Skeleton(width: 120, height: 14)],
              ),
            ),
          ],
        ),
        SizedBox(height: KairoSpacing.lg),
        Skeleton(height: 64, radius: KairoRadii.panel),
        SizedBox(height: KairoSpacing.lg),
        Skeleton(height: 48, radius: KairoRadii.pill),
        SizedBox(height: KairoSpacing.lg),
        Skeleton(height: 14),
        SizedBox(height: 8),
        Skeleton(height: 14),
        SizedBox(height: 8),
        Skeleton(width: 200, height: 14),
      ],
    );
  }
}
