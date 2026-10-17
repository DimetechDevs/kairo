import 'package:flutter/material.dart';

/// A streaming service Kairo recognises from a link.
class WatchService {
  const WatchService(this.name, this.color, {this.blocksInAppPlayback = false});

  final String name;
  final Color color;

  /// Services that refuse to play inside other apps' browsers (DRM / app-only policies).
  /// Their links open in the service's own app instead.
  final bool blocksInAppPlayback;
}

const _services = <String, WatchService>{
  'crunchyroll.com': WatchService('Crunchyroll', Color(0xFFF47521)),
  'bilibili.tv': WatchService('Bilibili', Color(0xFF00A1D6)),
  'bilibili.com': WatchService('Bilibili', Color(0xFF00A1D6)),
  'b23.tv': WatchService('Bilibili', Color(0xFF00A1D6)),
  'youtube.com': WatchService('YouTube', Color(0xFFFF0033)),
  'youtu.be': WatchService('YouTube', Color(0xFFFF0033)),
  'hidive.com': WatchService('HIDIVE', Color(0xFF00AEEF)),
  'tubitv.com': WatchService('Tubi', Color(0xFFFFFF13)),
  'retrocrush.tv': WatchService('RetroCrush', Color(0xFFE4002B)),
  'iq.com': WatchService('iQIYI', Color(0xFF00CC36)),
  'netflix.com': WatchService('Netflix', Color(0xFFE50914), blocksInAppPlayback: true),
  'primevideo.com': WatchService('Prime Video', Color(0xFF1399FF), blocksInAppPlayback: true),
  'amazon.com': WatchService('Prime Video', Color(0xFF1399FF), blocksInAppPlayback: true),
  'disneyplus.com': WatchService('Disney+', Color(0xFF113CCF), blocksInAppPlayback: true),
  'hulu.com': WatchService('Hulu', Color(0xFF1CE783), blocksInAppPlayback: true),
};

/// The known service for a link, matching the host or any parent domain (www., m., …).
WatchService? serviceFor(String url) {
  var host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  while (host.contains('.')) {
    final s = _services[host];
    if (s != null) return s;
    host = host.substring(host.indexOf('.') + 1);
  }
  return null;
}

/// A short name for any link: the service, or the bare host.
String linkLabel(String url) =>
    serviceFor(url)?.name ?? (Uri.tryParse(url.trim())?.host.replaceFirst(RegExp(r'^www\.'), '') ?? 'Link');

/// True for links to a video file or stream Kairo's own player can play (MP4, MKV, HLS, DASH).
bool isDirectMediaLink(String url) {
  final path = Uri.tryParse(url.trim())?.path.toLowerCase() ?? '';
  return RegExp(r'\.(mp4|m4v|mkv|webm|mov|avi|ts|m3u8|mpd)$').hasMatch(path);
}

/// Parses and checks a pasted link; returns null if it isn't a usable http(s) URL.
Uri? parseWatchLink(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  // Shared text often has words around the link ("Watch on Crunchyroll: https://…").
  final found = RegExp(r'https?://\S+').firstMatch(text);
  if (found != null) text = found.group(0)!;
  if (!text.startsWith('http')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || !uri.host.contains('.')) return null;
  return uri;
}
