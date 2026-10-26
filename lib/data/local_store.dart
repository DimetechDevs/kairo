import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Playback positions, kept on the phone.
///
/// Everything is loaded into memory when the app starts (it's small); writes go to disk in the background.
abstract class LocalStore {
  List<PlaybackProgress> get progress;

  Future<void> putProgress(PlaybackProgress progress);
}

/// For tests and as a fallback: nothing is written to disk.
class MemoryStore implements LocalStore {
  MemoryStore({List<PlaybackProgress> progress = const []})
      : _progress = {for (final pr in progress) (pr.animeId, pr.episode): pr};

  final Map<(int, int), PlaybackProgress> _progress;

  @override
  List<PlaybackProgress> get progress => _progress.values.toList();

  @override
  Future<void> putProgress(PlaybackProgress progress) async => _progress[(progress.animeId, progress.episode)] = progress;
}

class SqliteStore implements LocalStore {
  SqliteStore._(this._db, this.progress);

  final Database _db;
  @override
  final List<PlaybackProgress> progress;

  static Future<void> _createProgress(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS progress (
      anime_id INTEGER NOT NULL,
      episode INTEGER NOT NULL,
      position_ms INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (anime_id, episode)
    )''');

  static Future<SqliteStore> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'kairo.db'),
      version: 2,
      onCreate: (db, _) => _createProgress(db),
      // Version 1 also kept imported files; imports are gone, so that table goes too.
      onUpgrade: (db, from, _) async {
        if (from < 2) await db.execute('DROP TABLE IF EXISTS library_files');
        await _createProgress(db);
      },
    );

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
    return SqliteStore._(db, progress);
  }

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
