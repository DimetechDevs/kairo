import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Imported videos and playback positions, kept on the phone.
///
/// Everything is loaded into memory when the app starts (it's small); writes go to disk in the background.
abstract class LocalStore {
  List<LibraryFile> get files;
  List<PlaybackProgress> get progress;

  Future<void> putFile(LibraryFile file);
  Future<void> deleteFile(String id);
  Future<void> putProgress(PlaybackProgress progress);
}

/// For tests and as a fallback: nothing is written to disk.
class MemoryStore implements LocalStore {
  MemoryStore({List<LibraryFile> files = const [], List<PlaybackProgress> progress = const []})
      : _files = {for (final f in files) f.id: f},
        _progress = {for (final pr in progress) (pr.animeId, pr.episode): pr};

  final Map<String, LibraryFile> _files;
  final Map<(int, int), PlaybackProgress> _progress;

  @override
  List<LibraryFile> get files => _files.values.toList();
  @override
  List<PlaybackProgress> get progress => _progress.values.toList();

  @override
  Future<void> putFile(LibraryFile file) async => _files[file.id] = file;
  @override
  Future<void> deleteFile(String id) async => _files.remove(id);
  @override
  Future<void> putProgress(PlaybackProgress progress) async => _progress[(progress.animeId, progress.episode)] = progress;
}

class SqliteStore implements LocalStore {
  SqliteStore._(this._db, this.files, this.progress);

  final Database _db;
  @override
  final List<LibraryFile> files;
  @override
  final List<PlaybackProgress> progress;

  static Future<SqliteStore> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'kairo.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE library_files (
            id TEXT PRIMARY KEY,
            uri TEXT NOT NULL,
            file_name TEXT NOT NULL,
            size_bytes INTEGER,
            state TEXT NOT NULL,
            added_at INTEGER NOT NULL,
            anime_json TEXT,
            episode INTEGER,
            suggested_anime_json TEXT,
            suggested_episode INTEGER
          )''');
        await db.execute('''
          CREATE TABLE progress (
            anime_id INTEGER NOT NULL,
            episode INTEGER NOT NULL,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (anime_id, episode)
          )''');
      },
    );

    Anime? anime(Object? json) => json == null ? null : Anime.fromAniList(jsonDecode(json as String) as Map<String, dynamic>);

    final files = [
      for (final r in await db.query('library_files'))
        LibraryFile(
          id: r['id']! as String,
          uri: r['uri']! as String,
          fileName: r['file_name']! as String,
          sizeBytes: r['size_bytes'] as int?,
          state: FileState.values.byName(r['state']! as String),
          addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at']! as int),
          anime: anime(r['anime_json']),
          episode: r['episode'] as int?,
          suggestedAnime: anime(r['suggested_anime_json']),
          suggestedEpisode: r['suggested_episode'] as int?,
        ),
    ];
    final progress = [
      for (final r in await db.query('progress'))
        PlaybackProgress(
          animeId: r['anime_id']! as int,
          episode: r['episode']! as int,
          position: Duration(milliseconds: r['position_ms']! as int),
          duration: Duration(milliseconds: r['duration_ms']! as int),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
        ),
    ];
    return SqliteStore._(db, files, progress);
  }

  @override
  Future<void> putFile(LibraryFile f) => _db.insert(
        'library_files',
        {
          'id': f.id,
          'uri': f.uri,
          'file_name': f.fileName,
          'size_bytes': f.sizeBytes,
          'state': f.state.name,
          'added_at': f.addedAt.millisecondsSinceEpoch,
          'anime_json': f.anime == null ? null : jsonEncode(f.anime!.toJson()),
          'episode': f.episode,
          'suggested_anime_json': f.suggestedAnime == null ? null : jsonEncode(f.suggestedAnime!.toJson()),
          'suggested_episode': f.suggestedEpisode,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> deleteFile(String id) => _db.delete('library_files', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> putProgress(PlaybackProgress pr) => _db.insert(
        'progress',
        {
          'anime_id': pr.animeId,
          'episode': pr.episode,
          'position_ms': pr.position.inMilliseconds,
          'duration_ms': pr.duration.inMilliseconds,
          'updated_at': pr.updatedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
