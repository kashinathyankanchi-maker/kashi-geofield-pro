import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionHelper {
  /// Request location permissions (fine + coarse)
  static Future<bool> requestLocationPermission(BuildContext context) async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && context.mounted) {
      _showOpenSettingsDialog(context, 'Location');
    }
    return false;
  }

  /// Request storage permissions (for Android < 13)
  static Future<bool> requestStoragePermission(BuildContext context) async {
    // On Android 13+ we use READ_MEDIA_IMAGES etc., handled by file_picker natively
    if (await Permission.storage.isGranted) return true;
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && context.mounted) {
      _showOpenSettingsDialog(context, 'Storage');
    }
    return false;
  }

  /// Check if location is available
  static Future<bool> isLocationGranted() async {
    return await Permission.locationWhenInUse.isGranted;
  }

  static void _showOpenSettingsDialog(BuildContext context, String permName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$permName Permission Required'),
        content: Text(
          '$permName permission is permanently denied. Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
