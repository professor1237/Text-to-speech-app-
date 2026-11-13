import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LibraryDB {
  static Database? _db;
  static const _maxStoredCoverBytes = 512 * 1024;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'library.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE books('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'path TEXT UNIQUE, '
        'title TEXT, '
        'author TEXT, '
        'cover BLOB)',
      ),
    );
    return _db!;
  }

  static Future<List<Map<String, dynamic>>> all() async {
    final db = await _open();
    // Avoid loading unusually large embedded covers into every library row.
    // Older database versions may already contain oversized images.
    return db.rawQuery(
      'SELECT id, path, title, author, '
      'CASE WHEN length(cover) <= ? THEN cover ELSE NULL END AS cover '
      'FROM books ORDER BY id DESC',
      [_maxStoredCoverBytes],
    );
  }

  static Future<Uint8List?> _prepareCover(Uint8List? cover) async {
    if (cover == null || cover.isEmpty) return null;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        cover,
        targetWidth: 256,
        targetHeight: 384,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } catch (_) {
      // If decoding fails, only retain a small original image.
      return cover.length <= _maxStoredCoverBytes ? cover : null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Future<void> insert(
      String path, String title, String author, Uint8List? cover) async {
    final db = await _open();
    final safeCover = await _prepareCover(cover);
    await db.insert(
      'books',
      {'path': path, 'title': title, 'author': author, 'cover': safeCover},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> delete(int id) async {
    final db = await _open();
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }
}
