import 'package:flutter/material.dart';

import '../core/theme.dart';

class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, KairoSpacing.lg, KairoSpacing.gutter, KairoSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(text, style: KairoTheme.display(context), semanticsLabel: text)),
          ?trailing,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KairoSpacing.gutter),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: KairoColors.info),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Thin progress line used for episodes and list progress.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color = KairoColors.info, this.height = 4});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        color: color,
        backgroundColor: Colors.white.withValues(alpha: 0.15),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KairoSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: KairoColors.primary),
            const SizedBox(height: KairoSpacing.md),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: KairoSpacing.xs),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: KairoColors.textSecondary)),
            if (action != null) ...[const SizedBox(height: KairoSpacing.lg), action!],
          ],
        ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.pill),
        border: Border.all(color: KairoColors.outline),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// A selectable pill used for tabs and genre filters.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor = KairoColors.primary,
    this.selectedTextColor = KairoColors.text,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color selectedTextColor;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? selectedColor : KairoColors.outline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? selectedTextColor : KairoColors.text,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      trailing!,
                      style: TextStyle(fontSize: 13, color: (selected ? selectedTextColor : KairoColors.text).withValues(alpha: 0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
