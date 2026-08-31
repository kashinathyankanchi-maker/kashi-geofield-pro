import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class StorageHelper {
  /// Returns the path to the centralized 'kashi geofild pro' folder.
  /// On Android, it requests MANAGE_EXTERNAL_STORAGE and creates a public folder.
  /// On iOS/Desktop (or if permission denied), it falls back to the App Documents Directory.
  static Future<String> getAppStorageDirectory() async {
    if (Platform.isAndroid) {
      // Check/request modern "All files access" permission
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }
      
      // Fallback request for older Android versions
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }

      // If we have either permission, create the public folder
      if (await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted) {
        // Root of internal storage
        const internalStoragePath = '/storage/emulated/0';
        final folderPath = '$internalStoragePath/kashi geofild pro';
        
        final directory = Directory(folderPath);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        
        // Prevent Android MediaScanner from showing these files in the Gallery
        await _ensureNoMedia(directory.path);

        return directory.path;
      }
    }
    
    // Fallback for iOS, Desktop, or if Android permissions were permanently denied
    final dir = await getApplicationDocumentsDirectory();
    final folderPath = '${dir.path}/kashi geofild pro';
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    // Prevent MediaScanner scanning in fallback folder as well
    await _ensureNoMedia(directory.path);

    return directory.path;
  }

  /// Creates a .nomedia file in the given directory path so Android's
  /// Media Scanner ignores ALL media files (images, audio) inside it.
  /// Should be called every time a new app directory is created.
  static Future<void> _ensureNoMedia(String dirPath) async {
    try {
      final nomedia = File('$dirPath/.nomedia');
      if (!await nomedia.exists()) {
        await nomedia.create();
      }
    } catch (_) {}
  }

  /// Creates a subdirectory under [parentPath] and immediately places a
  /// .nomedia file inside so the gallery never indexes its contents.
  static Future<Directory> createHiddenSubDir(String parentPath, String name) async {
    final dir = Directory('$parentPath/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _ensureNoMedia(dir.path);
    return dir;
  }

  /// Places a .nomedia file in [dirPath] and all immediate subdirectories.
  /// Call this after extracting a KMZ or creating any folder with media.
  static Future<void> hideDirectoryFromGallery(String dirPath) async {
    await _ensureNoMedia(dirPath);
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          await _ensureNoMedia(entity.path);
        }
      }
    } catch (_) {}
  }
}
