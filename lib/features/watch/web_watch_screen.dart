import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../data/watch_links.dart';

/// Opens a streaming-site link the way the user prefers: inside Kairo, or in the service's own app
/// (always for services that refuse to play inside other apps).
Future<void> openWatchLink(BuildContext context, WidgetRef ref, String url, {int? animeId, int? episode}) async {
  final service = serviceFor(url);
  if (service?.blocksInAppPlayback == true || !ref.read(settingsProvider).openLinksInApp) {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open that link")));
    }
    return;
  }
  await context.push(Routes.watch(url, animeId: animeId, episode: episode));
}

/// A streaming site (Crunchyroll, Bilibili, YouTube, …) in Kairo's built-in browser.
/// The user signs in to the service here once; cookies keep them signed in.
class WebWatchScreen extends ConsumerStatefulWidget {
  const WebWatchScreen({super.key, required this.url, this.animeId, this.episode});

  final String url;
  final int? animeId;

  /// The episode being watched (null or 0 for a show's main page).
  final int? episode;

  @override
  ConsumerState<WebWatchScreen> createState() => _WebWatchScreenState();
}

class _WebWatchScreenState extends ConsumerState<WebWatchScreen> {
  late final WebViewController _web;
  String? _title;
  int _progress = 0;
  bool _canGoBack = false;
  String? _error;
  Widget? _fullscreen;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(KairoColors.background)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _error = null),
        onPageFinished: (_) async {
          final title = await _web.getTitle();
          final back = await _web.canGoBack();
          if (!mounted) return;
          setState(() {
            _title = title;
            _canGoBack = back;
          });
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) setState(() => _error = e.description);
        },
        // Links to other apps (intent://, market://, the service's app) go to Android.
        onNavigationRequest: (r) {
          final uri = Uri.tryParse(r.url);
          if (uri != null && uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'about' && uri.scheme != 'blob') {
            launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));

    if (_web.platform case final AndroidWebViewController android) {
      android.setMediaPlaybackRequiresUserGesture(false);
      // Crunchyroll and others play DRM-protected video; allow only that, nothing else (no camera/mic).
      android.setOnPlatformPermissionRequest((request) {
        final onlyDrm = request.types.every((t) => t == AndroidWebViewPermissionResourceType.protectedMediaId);
        onlyDrm ? request.grant() : request.deny();
      });
      // The site's own fullscreen button: show its video full screen, in landscape.
      android.setCustomWidgetCallbacks(
        onShowCustomWidget: (widget, onHidden) {
          SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          setState(() => _fullscreen = widget);
        },
        onHideCustomWidget: () {
          SystemChrome.setPreferredOrientations([]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          setState(() => _fullscreen = null);
        },
      );
    }
    final cookies = WebViewCookieManager();
    if (cookies.platform case final AndroidWebViewCookieManager android) {
      // Sign-in on several services goes through a separate login domain.
      android.setAcceptThirdPartyCookies(_web.platform as AndroidWebViewController, true);
    }
    _web.loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openOutside() async {
    final current = await _web.currentUrl() ?? widget.url;
    await launchUrl(Uri.parse(current), mode: LaunchMode.externalApplication);
  }

  void _markWatched() {
    final animeId = widget.animeId;
    final episode = widget.episode;
    final anime = animeId == null ? null : ref.read(animeProvider(animeId));
    if (anime == null || episode == null || episode < 1) return;
    ref.read(watchlistProvider.notifier).setWatched(anime, episode);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Marked episode $episode of ${anime.shortTitle} as watched')));
  }

  @override
  Widget build(BuildContext context) {
    final service = serviceFor(widget.url);
    final episode = widget.episode;
    final anime = widget.animeId == null ? null : ref.watch(animeProvider(widget.animeId!));
    final watched = anime == null ? 0 : ref.watch(watchlistProvider)[anime.id]?.watched ?? 0;
    final canMark = anime != null && episode != null && episode > 0;

    if (_fullscreen case final fullscreen?) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => _web.runJavaScript('document.exitFullscreen && document.exitFullscreen()'),
        child: ColoredBox(color: Colors.black, child: fullscreen),
      );
    }

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _web.goBack();
        final back = await _web.canGoBack();
        if (mounted) setState(() => _canGoBack = back);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(tooltip: 'Close', onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title?.isNotEmpty == true ? _title! : (service?.name ?? linkLabel(widget.url)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: service?.color ?? KairoColors.textMuted, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      [linkLabel(widget.url), if (canMark) 'Episode $episode'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            if (canMark)
              IconButton(
                tooltip: episode <= watched ? 'Episode $episode watched' : 'Mark episode $episode watched',
                onPressed: episode <= watched ? null : _markWatched,
                icon: Icon(
                  episode <= watched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  color: episode <= watched ? KairoColors.success : KairoColors.text,
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              color: KairoColors.surfaceRaised,
              onSelected: (v) => switch (v) {
                'reload' => _web.reload(),
                'outside' => _openOutside(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reload', child: Text('Reload')),
                PopupMenuItem(value: 'outside', child: Text('Open in ${service?.name ?? 'browser'} app')),
              ],
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: service?.color),
                )
              : null,
        ),
        body: _error == null
            ? WebViewWidget(controller: _web)
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(KairoSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 40, color: KairoColors.accent),
                      const SizedBox(height: KairoSpacing.md),
                      const Text("Couldn't load this page", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: KairoSpacing.xs),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: KairoColors.textSecondary)),
                      const SizedBox(height: KairoSpacing.lg),
                      Wrap(
                        spacing: KairoSpacing.sm,
                        runSpacing: KairoSpacing.sm,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(onPressed: _web.reload, child: const Text('Try again')),
                          OutlinedButton(onPressed: _openOutside, child: Text('Open in ${service?.name ?? 'browser'}')),
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
