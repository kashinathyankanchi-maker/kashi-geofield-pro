import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../models/kml_file_model.dart';
import '../models/polygon_model.dart';
import '../models/village_model.dart';
import '../models/print_history_model.dart';
import 'storage_helper.dart';

/// Handles full app data export (backup) and import (restore).
/// Backup format: a single `.kgfp` JSON file (Kashi GeoField Pack).
/// Contains: polygons, village_maps, kml_files (incl. file bytes), duty_diary,
///           print_history, SharedPreferences settings.
class BackupHelper {
  static const String _version = '1.0';
  static const String _ext = '.kgfp';

  // ─── EXPORT ────────────────────────────────────────────────────────────────

  /// Builds a full backup JSON, writes a `.kgfp` file, and opens the share sheet.
  static Future<BackupResult> exportAllData(BuildContext context) async {
    try {
      final db = DbHelper();

      // 1. Collect all SQLite data
      final polygons = await db.getAllPolygons();
      final villages = await db.getAllVillages();
      final kmlFiles = await db.getAllKmlFiles();
      final dutyDiaries = await db.getAllDutyDiaries();
      final printHistory = await db.getPrintHistory();

      // 2. Encode KML/KMZ and Marker media files as Base64
      final kmlPayloads = <Map<String, dynamic>>[];
      for (final kml in kmlFiles) {
        final map = kml.toMap();
        map.remove('id'); // Let the restore side auto-assign ID
        try {
          final file = File(kml.filepath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            map['file_bytes_b64'] = base64Encode(bytes);
          }
        } catch (_) {}
        kmlPayloads.add(map);
      }

      final polygonPayloads = <Map<String, dynamic>>[];
      for (final p in polygons) {
        final map = p.toMap();
        map.remove('id');
        try {
          if (p.photoPath != null && p.photoPath!.isNotEmpty) {
            final file = File(p.photoPath!);
            if (await file.exists()) {
              map['photo_bytes_b64'] = base64Encode(await file.readAsBytes());
            }
          }
          if (p.voiceNotePath != null && p.voiceNotePath!.isNotEmpty && p.voiceNotePath != 'voice_recorded') {
            final file = File(p.voiceNotePath!);
            if (await file.exists()) {
              map['voice_note_bytes_b64'] = base64Encode(await file.readAsBytes());
            }
          }
        } catch (_) {}
        polygonPayloads.add(map);
      }

      // 3. Collect SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefKeys = [
        'settings_gemini_api_key',
        'settings_org_name',
        'settings_officer_name',
        'settings_designation',
        'settings_default_polygon_color',
        'settings_offline_mode',
        'settings_fire_detection_alerts',
        'settings_auto_gps',
        'settings_units',
      ];
      final savedPrefs = <String, dynamic>{};
      for (final key in prefKeys) {
        final val = prefs.get(key);
        if (val != null) savedPrefs[key] = val;
      }

      // 4. Build payload JSON
      final payload = {
        'version': _version,
        'exported_at': DateTime.now().toIso8601String(),
        'polygons': polygonPayloads,
        'village_maps': villages.map((v) {
          final m = v.toMap();
          m.remove('id');
          return m;
        }).toList(),
        'kml_files': kmlPayloads,
        'duty_diary': dutyDiaries.map((d) {
          final m = Map<String, dynamic>.from(d);
          m.remove('id');
          return m;
        }).toList(),
        'print_history': printHistory.map((p) {
          final m = p.toMap();
          m.remove('id');
          return m;
        }).toList(),
        'settings': savedPrefs,
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

      // 5. Write file
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final backupFile = File('${tempDir.path}/kashi_backup_$ts$_ext');
      await backupFile.writeAsString(jsonStr, encoding: utf8);

      // 6. Share
      await Share.shareXFiles(
        [XFile(backupFile.path)],
        subject: 'Kashi GeoField Pro — App Data Backup',
        text: 'Transfer this backup file to your new device and use "Import / Restore" in Settings.',
      );

      final counts = {
        'polygons': polygons.length,
        'villages': villages.length,
        'kml_files': kmlFiles.length,
        'duty_diary': dutyDiaries.length,
      };
      return BackupResult.success(
        'Backup exported successfully!\n'
        '• ${counts['polygons']} Polygons\n'
        '• ${counts['villages']} Village Maps\n'
        '• ${counts['kml_files']} KML Files\n'
        '• ${counts['duty_diary']} Duty Diary Entries',
      );
    } catch (e) {
      return BackupResult.error('Export failed: $e');
    }
  }

  // ─── IMPORT ────────────────────────────────────────────────────────────────

  /// Picks a backup file (.kgfp, .db, .json, or any sync file), parses it, and restores all data.
  static Future<BackupResult> importData(BuildContext context, {File? externalFile}) async {
    try {
      String? pickedPath;

      if (externalFile != null) {
        pickedPath = externalFile.path;
      } else {
        // 1. Let user pick backup file (allow any extension since Android pickers may rename files)
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          dialogTitle: 'Select Kashi GeoField Backup (.kgfp or .db)',
        );

        if (result == null || result.files.isEmpty) {
          return BackupResult.cancelled('Import cancelled.');
        }
        pickedPath = result.files.first.path;
      }

      if (pickedPath == null || pickedPath.isEmpty) {
        return BackupResult.error('Could not read backup file path.');
      }

      final file = File(pickedPath);
      if (!await file.exists()) {
        return BackupResult.error('Backup file does not exist at selected path.');
      }

      final db = DbHelper();
      int polyCount = 0, villageCount = 0, kmlCount = 0, diaryCount = 0;

      // ── TYPE 1: Check if file is a SQLite database (.db or SQLite header bytes) ──
      bool isSqlite = pickedPath.toLowerCase().endsWith('.db');
      if (!isSqlite) {
        try {
          final headerBytes = await file.openRead(0, 16).first;
          final headerStr = String.fromCharCodes(headerBytes);
          if (headerStr.startsWith('SQLite format 3')) {
            isSqlite = true;
          }
        } catch (_) {}
      }

      if (isSqlite) {
        try {
          final backupDb = await openDatabase(pickedPath, readOnly: true);

          // Polygons
          try {
            final rows = await backupDb.query('polygons');
            for (final row in rows) {
              final copy = Map<String, dynamic>.from(row);
              copy.remove('id');
              await db.insertPolygon(PolygonModel.fromMap(row));
              polyCount++;
            }
          } catch (_) {}

          // Duty Diary
          try {
            final rows = await backupDb.query('duty_diary');
            for (final row in rows) {
              final copy = Map<String, dynamic>.from(row);
              copy.remove('id');
              await db.insertDutyDiary(copy);
              diaryCount++;
            }
          } catch (_) {}

          // Village Maps
          try {
            final rows = await backupDb.query('village_maps');
            for (final row in rows) {
              final copy = Map<String, dynamic>.from(row);
              copy.remove('id');
              await db.insertVillage(VillageModel.fromMap(row));
              villageCount++;
            }
          } catch (_) {}

          // KML Files
          try {
            final rows = await backupDb.query('kml_files');
            for (final row in rows) {
              await db.insertKmlFile(KmlFileModel.fromMap(row));
              kmlCount++;
            }
          } catch (_) {}

          await backupDb.close();
          await db.autoBackup();

          return BackupResult.success(
            'SQLite Database Backup Restored Successfully!\n'
            '• $polyCount Markers & Polygons\n'
            '• $villageCount Village Maps\n'
            '• $kmlCount KML Files\n'
            '• $diaryCount Duty Diary Entries\n\n'
            'Please restart the app or switch tabs to see your restored data.',
          );
        } catch (e) {
          // If SQLite open fails, fall back to JSON parsing below
        }
      }

      // ── TYPE 2: JSON Payload (.kgfp, .json, .txt, .bin) ──
      String jsonStr = '';
      try {
        jsonStr = await file.readAsString(encoding: utf8);
      } catch (_) {
        try {
          final bytes = await file.readAsBytes();
          jsonStr = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {}
      }

      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        }
      } catch (_) {}

      if (payload == null) {
        return BackupResult.error(
          'Unrecognized backup file format. Please select a valid .kgfp or .db backup file created by Kashi GeoField Pro.',
        );
      }

      final storageDir = await StorageHelper.getAppStorageDirectory();
      final docsDir = await getApplicationDocumentsDirectory();

      // ── Restore Polygons / Markers ──
      final polygons = payload['polygons'] as List? ?? [];
      for (final p in polygons) {
        try {
          String? photoPath = p['photo_path'] as String?;
          if (p['photo_bytes_b64'] != null) {
            final bytes = base64Decode(p['photo_bytes_b64'] as String);
            final imgFile = File('${docsDir.path}/img_${DateTime.now().millisecondsSinceEpoch}_${polyCount}.jpg');
            await imgFile.writeAsBytes(bytes);
            photoPath = imgFile.path;
          }

          String? voiceNotePath = p['voice_note_path'] as String?;
          if (p['voice_note_bytes_b64'] != null) {
            final bytes = base64Decode(p['voice_note_bytes_b64'] as String);
            final voiceFile = File('${docsDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}_${polyCount}.m4a');
            await voiceFile.writeAsBytes(bytes);
            voiceNotePath = voiceFile.path;
          }

          final model = PolygonModel(
            name: p['name'] as String? ?? 'Marker ${polyCount + 1}',
            coordinates: p['coordinates'] as String? ?? '[]',
            areaHectares: (p['area_hectares'] as num? ?? 0).toDouble(),
            perimeterMeters: (p['perimeter_meters'] as num? ?? 0).toDouble(),
            color: p['color'] as String? ?? '#2EA043',
            createdAt: p['created_at'] as String? ?? DateTime.now().toIso8601String(),
            description: p['description'] as String?,
            category: p['category'] as String?,
            photoPath: photoPath,
            voiceNotePath: voiceNotePath,
            officerName: p['officer_name'] as String?,
            gpsAccuracy: p['gps_accuracy'] as String?,
            altitude: p['altitude'] as String?,
          );
          await db.insertPolygon(model);
          polyCount++;
        } catch (_) {}
      }

      // ── Restore Village Maps ──
      final villages = payload['village_maps'] as List? ?? [];
      for (final v in villages) {
        try {
          final model = VillageModel(
            villageName: v['village_name'] as String? ?? 'Village',
            district: v['district'] as String? ?? '',
            state: v['state'] as String? ?? '',
            coordinates: v['coordinates'] as String? ?? '[]',
            areaHectares: (v['area_hectares'] as num? ?? 0).toDouble(),
            sourceFile: v['source_file'] as String? ?? '',
            createdAt: v['created_at'] as String? ?? DateTime.now().toIso8601String(),
          );
          await db.insertVillage(model);
          villageCount++;
        } catch (_) {}
      }

      // ── Restore KML Files ──
      final kmlFiles = payload['kml_files'] as List? ?? [];
      final kmlDir = Directory('$storageDir/kml_imports');
      if (!await kmlDir.exists()) await kmlDir.create(recursive: true);

      for (final k in kmlFiles) {
        try {
          final filename = k['filename'] as String? ?? 'layer.kml';
          String filepath = k['filepath'] as String? ?? '${kmlDir.path}/$filename';

          final b64 = k['file_bytes_b64'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            final bytes = base64Decode(b64);
            final destFile = File('${kmlDir.path}/$filename');
            await destFile.writeAsBytes(bytes);
            filepath = destFile.path;
          }

          final model = KmlFileModel(
            filename: filename,
            filepath: filepath,
            layerColor: k['layer_color'] as String? ?? '#2EA043',
            isVisible: (k['is_visible'] as int? ?? 1) == 1,
            opacity: (k['opacity'] as num? ?? 100).toDouble() / 100.0,
            smartOpacity: (k['smart_opacity'] as int? ?? 0) == 1,
            createdAt: k['created_at'] as String? ?? DateTime.now().toIso8601String(),
          );
          await db.insertKmlFile(model);
          kmlCount++;
        } catch (_) {}
      }

      // ── Restore Duty Diary ──
      final diary = payload['duty_diary'] as List? ?? [];
      for (final d in diary) {
        try {
          await db.insertDutyDiary({
            'date': d['date'] ?? DateTime.now().toString().substring(0, 10),
            'time': d['time'] ?? '',
            'locations': d['locations'] ?? '',
            'activities': d['activities'] ?? '',
            'distance': (d['distance'] as num? ?? 0).toDouble(),
            'camp_station': d['camp_station'] ?? '',
            'departure_time': d['departure_time'] ?? '',
            'places_visited': d['places_visited'] ?? '',
            'return_time': d['return_time'] ?? '',
            'mode_and_km': d['mode_and_km'] ?? '',
            'work_done': d['work_done'] ?? '',
            'created_at': d['created_at'] ?? DateTime.now().toIso8601String(),
          });
          diaryCount++;
        } catch (_) {}
      }

      // ── Restore Settings ──
      final settings = payload['settings'] as Map<String, dynamic>? ?? {};
      if (settings.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        for (final entry in settings.entries) {
          final v = entry.value;
          if (v is String) await prefs.setString(entry.key, v);
          if (v is bool) await prefs.setBool(entry.key, v);
          if (v is int) await prefs.setInt(entry.key, v);
          if (v is double) await prefs.setDouble(entry.key, v);
        }
      }

      // Update persistent external backup immediately
      await db.autoBackup();

      return BackupResult.success(
        'Restore Completed Successfully!\n'
        '• $polyCount Markers & Polygons\n'
        '• $villageCount Village Maps\n'
        '• $kmlCount KML Files\n'
        '• $diaryCount Duty Diary Entries\n\n'
        'All data is saved and backed up. Switch tabs or restart app to update map display.',
      );
    } catch (e) {
      return BackupResult.error('Import failed: $e');
    }
  }
}

/// Result model for backup/restore operations.
class BackupResult {
  final bool success;
  final bool cancelled;
  final String message;

  BackupResult._({required this.success, required this.cancelled, required this.message});

  factory BackupResult.success(String message) =>
      BackupResult._(success: true, cancelled: false, message: message);

  factory BackupResult.error(String message) =>
      BackupResult._(success: false, cancelled: false, message: message);

  factory BackupResult.cancelled(String message) =>
      BackupResult._(success: false, cancelled: true, message: message);
}
