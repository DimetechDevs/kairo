import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/anilist_sync.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../widgets/common.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  void _update(KairoSettings Function(KairoSettings s) change) => ref.read(settingsProvider.notifier).update(change);

  /// Shows the options in a sheet and saves the chosen one.
  Future<void> _pick<T>(
    String title,
    Map<T, String> options,
    T current,
    KairoSettings Function(KairoSettings s, T value) apply,
  ) async {
    final chosen = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: KairoSpacing.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 0, KairoSpacing.gutter, KairoSpacing.sm),
              child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            for (final o in options.entries)
              ListTile(
                leading: Icon(
                  o.key == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: o.key == current ? KairoColors.primarySoft : KairoColors.textMuted,
                ),
                title: Text(o.value),
                onTap: () => Navigator.pop(context, o.key),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _update((s) => apply(s, chosen));
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(watchlistProvider).values;
    final episodes = entries.fold<int>(0, (sum, e) => sum + e.watched);
    final minutes = entries.fold<int>(0, (sum, e) => sum + e.watched * (e.anime.duration ?? 24));
    final completed = entries.where((e) => e.status == ListStatus.completed).length;
    final files = ref.watch(libraryProvider).length;
    final settings = ref.watch(settingsProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: KairoSpacing.xxl),
        children: [
          const ScreenTitle('Profile'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AccountCard(),
                const SizedBox(height: KairoSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(value: '$episodes', label: 'Episodes', color: KairoColors.primarySoft),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        value: '${(minutes / 60).round()} h',
                        label: 'Watched',
                        color: KairoColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(value: '$completed', label: 'Completed', color: KairoColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const _GroupLabel('Player defaults'),
                _SettingsGroup(
                  children: [
                    _ValueRow(
                      label: 'Playback speed',
                      value: '${settings.speed}×',
                      onTap: () => _pick(
                        'Playback speed',
                        {
                          for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0]) s: '$s×',
                        },
                        settings.speed,
                        (s, v) => s.copyWith(speed: v),
                      ),
                    ),
                    _ValueRow(
                      label: 'Subtitle language',
                      value: subtitleLanguages[settings.subtitleLanguage]!,
                      onTap: () => _pick(
                        'Subtitle language',
                        subtitleLanguages,
                        settings.subtitleLanguage,
                        (s, v) => s.copyWith(subtitleLanguage: v),
                      ),
                    ),
                    _ValueRow(
                      label: 'Audio language',
                      value: audioLanguages[settings.audioLanguage]!,
                      onTap: () => _pick(
                        'Audio language',
                        audioLanguages,
                        settings.audioLanguage,
                        (s, v) => s.copyWith(audioLanguage: v),
                      ),
                    ),
                    _ValueRow(
                      label: 'Count as watched at',
                      value: '${(settings.watchedAt * 100).round()}%',
                      onTap: () => _pick(
                        'Count as watched at',
                        {
                          for (final w in const [0.8, 0.85, 0.9, 0.95]) w: '${(w * 100).round()}%',
                        },
                        settings.watchedAt,
                        (s, v) => s.copyWith(watchedAt: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const _GroupLabel('Playback'),
                _SettingsGroup(
                  children: [
                    SwitchListTile(
                      title: const Text('Play next episode automatically', style: TextStyle(fontSize: 14)),
                      value: settings.autoNext,
                      onChanged: (v) => _update((s) => s.copyWith(autoNext: v)),
                    ),
                    SwitchListTile(
                      title: const Text('Show Skip intro button', style: TextStyle(fontSize: 14)),
                      value: settings.skipIntro,
                      onChanged: (v) => _update((s) => s.copyWith(skipIntro: v)),
                    ),
                    if (settings.skipIntro)
                      _ValueRow(
                        label: 'Skip intro jumps',
                        value: '${settings.skipSeconds} s',
                        onTap: () => _pick(
                          'Skip intro jumps',
                          {
                            for (final sec in const [60, 75, 85, 90, 105]) sec: '$sec seconds',
                          },
                          settings.skipSeconds,
                          (s, v) => s.copyWith(skipSeconds: v),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const _GroupLabel('Notifications'),
                _SettingsGroup(
                  children: [
                    SwitchListTile(
                      title: const Text('New episode alerts', style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                        "When a show you're watching or planning airs a new episode",
                        style: TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                      ),
                      value: settings.airingAlerts,
                      onChanged: (v) => _update((s) => s.copyWith(airingAlerts: v)),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const _GroupLabel('Storage and sync'),
                _SettingsGroup(
                  children: [
                    _ValueRow(
                      label: 'Imported videos',
                      value: '$files ${files == 1 ? 'video' : 'videos'}',
                      onTap: () => StatefulNavigationShell.of(context).goBranch(3),
                    ),
                    _ValueRow(
                      label: 'Cloud sync',
                      value: ref.watch(aniListSyncProvider).signedIn ? 'AniList · On' : 'Off · Guest',
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const Text(
                  'Anime information from AniList',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: KairoColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(color: KairoColors.surface, borderRadius: BorderRadius.circular(KairoRadii.panel)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary)),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KairoSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: KairoColors.textSecondary,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KairoColors.surface,
      borderRadius: BorderRadius.circular(KairoRadii.panel),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const Divider(height: 1, color: KairoColors.surfaceRaised),
          ],
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.lg, vertical: KairoSpacing.sm),
          child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
              const SizedBox(width: KairoSpacing.sm),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 14, color: KairoColors.textSecondary),
                ),
              ),
              const SizedBox(width: 4),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: KairoColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Guest or signed-in AniList account, with sign-in, sync and sign-out.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(aniListSyncProvider);
    final notifier = ref.read(aniListSyncProvider.notifier);
    final user = sync.user;
    final subtitle = switch ((user, sync.syncing, sync.lastSync)) {
      (null, _, _) => 'Your list is saved on this phone',
      (_, true, _) => 'Syncing with AniList…',
      (_, false, final DateTime t) => 'Synced with AniList · ${_ago(t)}',
      _ => 'Signed in with AniList',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2F2B47)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: KairoColors.primary,
                foregroundImage: user?.avatarUrl == null ? null : CachedNetworkImageProvider(user!.avatarUrl!),
                child: Text(
                  (user?.name ?? 'Guest').characters.first.toUpperCase(),
                  style: const TextStyle(color: KairoColors.text, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'Guest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (sync.error != null) ...[
            const SizedBox(height: KairoSpacing.md),
            Text(sync.error!, style: const TextStyle(fontSize: 13, color: KairoColors.accent)),
          ],
          const SizedBox(height: 14),
          if (user == null)
            FilledButton.icon(
              onPressed: sync.syncing ? null : notifier.signIn,
              style: FilledButton.styleFrom(backgroundColor: KairoColors.text, foregroundColor: KairoColors.background),
              icon: sync.syncing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded),
              label: const Text('Sign in with AniList to sync', maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: sync.syncing ? null : notifier.syncNow,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Sync now', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: KairoSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: sync.syncing
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: KairoColors.surface,
                                title: const Text('Sign out of AniList?'),
                                content: const Text('Your list stays on this phone. It just stops syncing.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Sign out'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await notifier.signOut();
                          },
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Sign out', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
