import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/theme.dart';

void main() {
  runApp(const ProviderScope(child: KairoApp()));
}

class KairoApp extends StatelessWidget {
  const KairoApp({super.key, this.useGoogleFonts = true});

  /// Tests turn this off so they don't try to download fonts.
  final bool useGoogleFonts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kairo',
      debugShowCheckedModeBanner: false,
      theme: KairoTheme.dark(useGoogleFonts: useGoogleFonts),
      routerConfig: createRouter(),
    );
  }
}
