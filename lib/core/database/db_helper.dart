import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/polygon_model.dart';
import '../models/village_model.dart';
import '../models/kml_file_model.dart';
import '../models/print_history_model.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  static Database? _db;

  factory DbHelper() => _instance;
  DbHelper._internal();

  static const String _dbName = 'kashi_geofield.db';
  static const int _dbVersion = 7;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(path, version: _dbVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE polygons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        coordinates TEXT NOT NULL,
        area_hectares REAL NOT NULL,
        perimeter_meters REAL NOT NULL,
        color TEXT NOT NULL,
        created_at TEXT NOT NULL,
        description TEXT,
        category TEXT,
        photo_path TEXT,
        voice_note_path TEXT,
        officer_name TEXT,
        gps_accuracy TEXT,
        altitude TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE village_maps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        village_name TEXT NOT NULL,
        district TEXT,
        state TEXT,
        coordinates TEXT NOT NULL,
        area_hectares REAL NOT NULL,
        source_file TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE kml_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filename TEXT NOT NULL,
        filepath TEXT NOT NULL,
        layer_color TEXT DEFAULT '#2EA043',
        is_visible INTEGER DEFAULT 1,
        opacity INTEGER DEFAULT 100,
        smart_opacity INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE print_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        map_type TEXT NOT NULL,
        map_name TEXT NOT NULL,
        pdf_path TEXT NOT NULL,
        printed_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE duty_diary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        locations TEXT NOT NULL,
        activities TEXT NOT NULL,
        distance REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS duty_diary (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          time TEXT NOT NULL,
          locations TEXT NOT NULL,
          activities TEXT NOT NULL,
          distance REAL NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS kml_files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          filename TEXT NOT NULL,
          filepath TEXT NOT NULL,
          layer_color TEXT DEFAULT '#2EA043',
          is_visible INTEGER DEFAULT 1,
          opacity INTEGER DEFAULT 100,
          smart_opacity INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS print_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          polygon_id INTEGER,
          file_path TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // Recreate print_history with correct schema (map_type, map_name, pdf_path, printed_at)
      await db.execute('DROP TABLE IF EXISTS print_history');
      await db.execute('''
        CREATE TABLE print_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          map_type TEXT NOT NULL,
          map_name TEXT NOT NULL,
          pdf_path TEXT NOT NULL,
          printed_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      // Add opacity column to kml_files (0-100 integer, default 100 = fully opaque)
      try {
        await db.execute(
            'ALTER TABLE kml_files ADD COLUMN opacity INTEGER DEFAULT 100');
      } catch (_) {
        // Column may already exist
      }
    }
    if (oldVersion < 5) {
      // Add smart_opacity column to kml_files
      try {
        await db.execute(
            'ALTER TABLE kml_files ADD COLUMN smart_opacity INTEGER DEFAULT 0');
      } catch (_) {
        // Column may already exist
      }
    }
    if (oldVersion < 6) {
      // Catch-all to fix broken v5 installs where smart_opacity wasn't in _onCreate
      try {
        await db.execute(
            'ALTER TABLE kml_files ADD COLUMN smart_opacity INTEGER DEFAULT 0');
      } catch (e) {
        // Table already created
      }
    }

    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE polygons ADD COLUMN description TEXT;');
        await db.execute('ALTER TABLE polygons ADD COLUMN category TEXT;');
        await db.execute('ALTER TABLE polygons ADD COLUMN photo_path TEXT;');
        await db.execute('ALTER TABLE polygons ADD COLUMN voice_note_path TEXT;');
        await db.execute('ALTER TABLE polygons ADD COLUMN officer_name TEXT;');
        await db.execute('ALTER TABLE polygons ADD COLUMN gps_accuracy TEXT;');
        await db.execute('ALTER TABLE polygons ADD COLUMN altitude TEXT;');
      } catch (e) {
        // Columns might already exist if previously added manually
      }
    }
  }

  // ── Duty Diary ─────────────────────────────────────────────────────────────

  Future<int> insertDutyDiary(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('duty_diary', row);
  }

  Future<List<Map<String, dynamic>>> getAllDutyDiaries() async {
    final db = await database;
    return await db.query('duty_diary', orderBy: 'date DESC, time DESC');
  }

  Future<int> updateDutyDiary(Map<String, dynamic> row) async {
    final db = await database;
    int id = row['id'] as int;
    return await db.update('duty_diary', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteDutyDiary(int id) async {
    final db = await database;
    return await db.delete('duty_diary', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────── POLYGONS ──────────────────────────────────────────────

  Future<int> insertPolygon(PolygonModel polygon) async {
    final db = await database;
    return db.insert('polygons', polygon.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PolygonModel>> getAllPolygons() async {
    final db = await database;
    final maps = await db.query('polygons', orderBy: 'created_at DESC');
    return maps.map(PolygonModel.fromMap).toList();
  }

  Future<PolygonModel?> getPolygonById(int id) async {
    final db = await database;
    final maps = await db.query('polygons', where: 'id = ?', whereArgs: [id]);
    return maps.isEmpty ? null : PolygonModel.fromMap(maps.first);
  }

  Future<int> updatePolygon(PolygonModel polygon) async {
    final db = await database;
    return db.update('polygons', polygon.toMap(),
        where: 'id = ?', whereArgs: [polygon.id]);
  }

  Future<int> deletePolygon(int id) async {
    final db = await database;
    return db.delete('polygons', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllPolygons() async {
    final db = await database;
    return db.delete('polygons');
  }

  // ─────────────────── VILLAGES ──────────────────────────────────────────────

  Future<int> insertVillage(VillageModel village) async {
    final db = await database;
    return db.insert('village_maps', village.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<VillageModel>> getAllVillages() async {
    final db = await database;
    final maps = await db.query('village_maps', orderBy: 'village_name ASC');
    return maps.map(VillageModel.fromMap).toList();
  }

  Future<List<VillageModel>> searchVillages(String query) async {
    final db = await database;
    final maps = await db.query(
      'village_maps',
      where: 'village_name LIKE ? OR district LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'village_name ASC',
    );
    return maps.map(VillageModel.fromMap).toList();
  }

  Future<int> deleteVillage(int id) async {
    final db = await database;
    return db.delete('village_maps', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllVillages() async {
    final db = await database;
    return db.delete('village_maps');
  }

  // ─────────────────── KML FILES ─────────────────────────────────────────────

  Future<int> insertKmlFile(KmlFileModel kml) async {
    final db = await database;
    return db.insert('kml_files', kml.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<KmlFileModel>> getAllKmlFiles() async {
    final db = await database;
    final maps = await db.query('kml_files', orderBy: 'created_at DESC');
    return maps.map(KmlFileModel.fromMap).toList();
  }

  Future<int> updateKmlVisibility(int id, bool isVisible) async {
    final db = await database;
    return db.update(
      'kml_files',
      {'is_visible': isVisible ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateKmlColor(int id, String color) async {
    final db = await database;
    return db.update(
      'kml_files',
      {'layer_color': color},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateKmlOpacity(int id, int opacity) async {
    final db = await database;
    return db.update(
      'kml_files',
      {'opacity': opacity.clamp(0, 100)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteKmlFile(int id) async {
    final db = await database;
    return db.delete('kml_files', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────── PRINT HISTORY ─────────────────────────────────────────

  Future<int> insertPrintHistory(PrintHistoryModel history) async {
    final db = await database;
    return db.insert('print_history', history.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PrintHistoryModel>> getPrintHistory() async {
    final db = await database;
    final maps = await db.query('print_history', orderBy: 'printed_at DESC', limit: 100);
    return maps.map(PrintHistoryModel.fromMap).toList();
  }

  Future<int> deletePrintHistory(int id) async {
    final db = await database;
    return db.delete('print_history', where: 'id = ?', whereArgs: [id]);
  }

  // Alias methods for settings screen compatibility
  Future<int> clearAllPolygons() => deleteAllPolygons();
  Future<int> clearPrintHistory() async {
    final db = await database;
    return db.delete('print_history');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

