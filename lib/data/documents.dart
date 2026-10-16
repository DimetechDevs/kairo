import 'package:flutter/services.dart';

/// A file chosen in the system document picker.
class PickedDocument {
  const PickedDocument({required this.uri, required this.name, this.size});

  final String uri;
  final String name;
  final int? size;
}

/// The Android document picker (see MainActivity.kt). Files stay where they are; Kairo keeps
/// permission to read them across restarts.
class Documents {
  const Documents();

  static const _channel = MethodChannel('kairo/documents');

  Future<List<PickedDocument>> pick({List<String> mimeTypes = const ['video/*'], bool multiple = true}) async {
    final picked = await _channel.invokeListMethod<Map<Object?, Object?>>('pick', {
      'mimeTypes': mimeTypes,
      'multiple': multiple,
    });
    return [
      for (final p in picked ?? const <Map<Object?, Object?>>[])
        PickedDocument(uri: p['uri']! as String, name: p['name']! as String, size: p['size'] as int?),
    ];
  }

  Future<List<PickedDocument>> pickVideos() => pick();

  Future<PickedDocument?> pickVideo() async => (await pick(multiple: false)).firstOrNull;

  /// Subtitle files report all sorts of MIME types, so any file is allowed.
  Future<PickedDocument?> pickSubtitle() async => (await pick(mimeTypes: const ['*/*'], multiple: false)).firstOrNull;

  /// False when the file was moved, deleted or its permission was lost.
  Future<bool> exists(String uri) async => await _channel.invokeMethod<bool>('exists', {'uri': uri}) ?? false;

  Future<void> release(String uri) => _channel.invokeMethod('release', {'uri': uri});

  Future<Uint8List?> readBytes(String uri) => _channel.invokeMethod<Uint8List>('readText', {'uri': uri});
}
