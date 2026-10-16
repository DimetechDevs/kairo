import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _autoNext = true;
  bool _skipIntro = true;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(watchlistProvider).values;
    final episodes = entries.fold<int>(0, (sum, e) => sum + e.watched);
    final minutes = entries.fold<int>(0, (sum, e) => sum + e.watched * (e.anime.duration ?? 24));
    final completed = entries.where((e) => e.status == ListStatus.completed).length;
    final files = ref.watch(libraryProvider).length;

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
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: KairoColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF2F2B47)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: KairoColors.primary,
                            child: Text(
                              'G',
                              style: TextStyle(color: KairoColors.text, fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Guest', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                Text(
                                  'Your list is saved on this phone',
                                  style: TextStyle(fontSize: 13, color: KairoColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () =>
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('Accounts and sync come in phase 2.'))),
                        style: FilledButton.styleFrom(
                          backgroundColor: KairoColors.text,
                          foregroundColor: KairoColors.background,
                        ),
                        child: const Text('Sign in to back up and sync'),
                      ),
                    ],
                  ),
                ),
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
                const _SettingsGroup(
                  children: [
                    _ValueRow(label: 'Playback speed', value: '1.0×'),
                    _ValueRow(label: 'Subtitle language', value: 'English'),
                    _ValueRow(label: 'Count as watched at', value: '90%'),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const _GroupLabel('Playback'),
                _SettingsGroup(
                  children: [
                    SwitchListTile(
                      title: const Text('Play next episode automatically', style: TextStyle(fontSize: 14)),
                      value: _autoNext,
                      onChanged: (v) => setState(() => _autoNext = v),
                    ),
                    SwitchListTile(
                      title: const Text('Show Skip intro button', style: TextStyle(fontSize: 14)),
                      value: _skipIntro,
                      onChanged: (v) => setState(() => _skipIntro = v),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.xl),
                const _GroupLabel('Storage and sync'),
                _SettingsGroup(
                  children: [
                    _ValueRow(label: 'Imported videos', value: '$files files'),
                    const _ValueRow(label: 'Cloud sync', value: 'Off · Guest'),
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
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
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
              const Icon(Icons.chevron_right_rounded, size: 18, color: KairoColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
