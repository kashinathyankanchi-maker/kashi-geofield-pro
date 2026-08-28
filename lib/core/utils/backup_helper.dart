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

      // 2. Encode KML/KMZ file bytes as Base64
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
        'polygons': polygons.map((p) {
          final m = p.toMap();
          m.remove('id');
          return m;
        }).toList(),
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

  /// Picks a `.kgfp` file, parses it, and restores all data.
  static Future<BackupResult> importData(BuildContext context) async {
    try {
      // 1. Let user pick backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        dialogTitle: 'Select Kashi GeoField Backup (.kgfp)',
      );

      if (result == null || result.files.isEmpty) {
        return BackupResult.cancelled('Import cancelled.');
      }

      final pickedPath = result.files.first.path;
      if (pickedPath == null) {
        return BackupResult.error('Could not read backup file path.');
      }

      // Validate extension
      if (!pickedPath.endsWith(_ext)) {
        return BackupResult.error(
          'Invalid file type. Please select a .kgfp backup file created by Kashi GeoField Pro.');
      }

      final file = File(pickedPath);
      final jsonStr = await file.readAsString(encoding: utf8);
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 2. Restore all data
      final db = DbHelper();
      final storageDir = await StorageHelper.getAppStorageDirectory();

      int polyCount = 0, villageCount = 0, kmlCount = 0, diaryCount = 0;

      // ── Polygons ──
      final polygons = payload['polygons'] as List? ?? [];
      for (final p in polygons) {
        try {
          final model = PolygonModel(
            name: p['name'] as String,
            coordinates: p['coordinates'] as String,
            areaHectares: (p['area_hectares'] as num).toDouble(),
            perimeterMeters: (p['perimeter_meters'] as num).toDouble(),
            color: p['color'] as String? ?? '#2EA043',
            createdAt: p['created_at'] as String? ?? DateTime.now().toIso8601String(),
          );
          await db.insertPolygon(model);
          polyCount++;
        } catch (_) {}
      }

      // ── Village Maps ──
      final villages = payload['village_maps'] as List? ?? [];
      for (final v in villages) {
        try {
          final model = VillageModel(
            villageName: v['village_name'] as String,
            district: v['district'] as String? ?? '',
            state: v['state'] as String? ?? '',
            coordinates: v['coordinates'] as String,
            areaHectares: (v['area_hectares'] as num).toDouble(),
            sourceFile: v['source_file'] as String? ?? '',
            createdAt: v['created_at'] as String? ?? DateTime.now().toIso8601String(),
          );
          await db.insertVillage(model);
          villageCount++;
        } catch (_) {}
      }

      // ── KML Files (restore physical file then DB record) ──
      final kmlFiles = payload['kml_files'] as List? ?? [];
      final kmlDir = Directory('$storageDir/kml_imports');
      if (!await kmlDir.exists()) await kmlDir.create(recursive: true);

      for (final k in kmlFiles) {
        try {
          final filename = k['filename'] as String;
          String filepath = k['filepath'] as String? ?? '$storageDir/kml_imports/$filename';

          // Restore the physical file if bytes were backed up
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

      // ── Duty Diary ──
      final diary = payload['duty_diary'] as List? ?? [];
      for (final d in diary) {
        try {
          await db.insertDutyDiary({
            'date': d['date'],
            'time': d['time'],
            'locations': d['locations'],
            'activities': d['activities'],
            'distance': (d['distance'] as num).toDouble(),
            'created_at': d['created_at'] ?? DateTime.now().toIso8601String(),
          });
          diaryCount++;
        } catch (_) {}
      }

      // ── Settings ──
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

      return BackupResult.success(
        'Restore completed successfully!\n'
        '• $polyCount Polygons\n'
        '• $villageCount Village Maps\n'
        '• $kmlCount KML Files\n'
        '• $diaryCount Duty Diary Entries\n\n'
        'Restart the app for all data to appear on the map.',
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
