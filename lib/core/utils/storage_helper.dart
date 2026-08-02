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
        final nomedia = File('${directory.path}/.nomedia');
        if (!await nomedia.exists()) {
          await nomedia.create();
        }

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
    final nomedia = File('${directory.path}/.nomedia');
    if (!await nomedia.exists()) {
      await nomedia.create();
    }

    return directory.path;
  }
}
