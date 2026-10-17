import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/details/details_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/my_anime/my_anime_screen.dart';
import '../features/player/player_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/watch/web_watch_screen.dart';
import 'shell.dart';

abstract final class Routes {
  static const home = '/';
  static const discover = '/discover';
  static const myAnime = '/my-anime';
  static const library = '/library';
  static const profile = '/profile';

  static String anime(int id) => '/anime/$id';
  static String player(int animeId, int episode) => '/player/$animeId/$episode';
  static String watch(String url, {int? animeId, int? episode}) => Uri(path: '/watch', queryParameters: {
        'url': url,
        if (animeId != null) 'anime': '$animeId',
        if (episode != null) 'ep': '$episode',
      }).toString();
}

GoRouter createRouter() {
  final rootKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => KairoShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.discover, builder: (_, _) => const DiscoverScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.myAnime, builder: (_, _) => const MyAnimeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.library, builder: (_, _) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      // Details and the player open above the tab bar, as separate routes.
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/anime/:id',
        builder: (_, state) => DetailsScreen(animeId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/player/:animeId/:episode',
        builder: (_, state) => PlayerScreen(
          animeId: int.parse(state.pathParameters['animeId']!),
          episode: int.parse(state.pathParameters['episode']!),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootKey,
        path: '/watch',
        builder: (_, state) => WebWatchScreen(
          url: state.uri.queryParameters['url']!,
          animeId: int.tryParse(state.uri.queryParameters['anime'] ?? ''),
          episode: int.tryParse(state.uri.queryParameters['ep'] ?? ''),
        ),
      ),
    ],
  );
}
