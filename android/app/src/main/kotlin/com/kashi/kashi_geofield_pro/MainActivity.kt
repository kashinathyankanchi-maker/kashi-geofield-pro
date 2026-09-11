package com.kashi.kashi_geofield_pro

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.kashi.geofield/file_utils"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // Returns the display name for a content:// URI
                    "getFileName" -> {
                        val uriStr = call.argument<String>("uri") ?: ""
                        try {
                            val uri = Uri.parse(uriStr)
                            val name = getFileNameFromUri(contentResolver, uri)
                            result.success(name)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // Reads all bytes from a content:// or file:// URI
                    "readUriBytes" -> {
                        val uriStr = call.argument<String>("uri") ?: ""
                        try {
                            val uri = Uri.parse(uriStr)
                            val bytes = readBytesFromUri(contentResolver, uri)
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("READ_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun getFileNameFromUri(resolver: ContentResolver, uri: Uri): String {
        var name = ""
        // Try the content provider display name column
        val cursor: Cursor? = resolver.query(uri, null, null, null, null)
        cursor?.use {
            val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && it.moveToFirst()) {
                name = it.getString(idx) ?: ""
            }
        }
        // Fallback: last path segment
        if (name.isEmpty()) {
            name = uri.lastPathSegment ?: "imported_file.kmz"
        }
        return name
    }

    private fun readBytesFromUri(resolver: ContentResolver, uri: Uri): ByteArray {
        resolver.openInputStream(uri)?.use { stream ->
            return stream.readBytes()
        }
        throw Exception("Could not open input stream for URI: $uri")
    }
}
