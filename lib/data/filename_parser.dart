/// Guesses the show and episode from a video file name, e.g.
/// `[SubsPlease] Sousou no Frieren - 03 (1080p) [ABCD1234].mkv` → ("Sousou no Frieren", 3).
({String title, int? episode}) parseVideoName(String fileName) {
  var name = fileName;

  // Drop the extension.
  final dot = name.lastIndexOf('.');
  if (dot > 0 && name.length - dot <= 5) name = name.substring(0, dot);

  // Release-group tags, resolutions, codecs and checksums in brackets.
  name = name.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ');
  name = name.replaceAll(RegExp(r'[._]+'), ' ');

  int? episode;
  final patterns = [
    RegExp(r'\bS\d{1,2}\s*E(\d{1,4})\b', caseSensitive: false), // S01E03
    RegExp(r'\b(?:Episode|Ep|E)\s*(\d{1,4})\b', caseSensitive: false), // Episode 3, Ep03, E03
    RegExp(r'\s-\s*(\d{1,4})(?:v\d)?\b'), // " - 03", " - 03v2"
    RegExp(r'#(\d{1,4})\b'), // #03
    RegExp(r'\b(\d{1,4})(?:v\d)?\s*$'), // trailing number
  ];
  for (final p in patterns) {
    final m = p.firstMatch(name);
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    // Skip things that are clearly years or resolutions.
    if (n >= 1900 && n <= 2100 || n == 720 || n == 1080 || n == 480 || n == 2160) continue;
    episode = n;
    name = name.substring(0, m.start);
    break;
  }

  final title = name
      .replaceAll(RegExp(r'\b(?:1080p|720p|480p|2160p|4k|x264|x265|hevc|web-?dl|bluray|bd|multi|dual audio)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\bS\d{1,2}\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[-–]+\s*$'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return (title: title, episode: episode);
}
