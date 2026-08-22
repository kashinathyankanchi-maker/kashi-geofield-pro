# Flutter + Plugin ProGuard rules — kashi_geofield_pro

# ── Flutter ───────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class io.flutter.plugins.** { *; }

# ── Google ML Kit (OCR / Text Recognition) ───────────────────────────────────
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── Syncfusion PDF Viewer ─────────────────────────────────────────────────────
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**

# ── pdfx (PDF rendering) ──────────────────────────────────────────────────────
-keep class com.example.pdfx.** { *; }
-dontwarn com.example.pdfx.**

# ── Speech to Text ────────────────────────────────────────────────────────────
-keep class com.csdcorp.speech_to_text.** { *; }
-dontwarn com.csdcorp.speech_to_text.**

# ── Geolocator ────────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ── Permission Handler ────────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── AR Flutter Plugin ─────────────────────────────────────────────────────────
-keep class io.github.the_bharat.ar_flutter_plugin_plus.** { *; }
-dontwarn io.github.the_bharat.ar_flutter_plugin_plus.**

# ── WebView ───────────────────────────────────────────────────────────────────
-keep class androidx.webkit.** { *; }
-keep class android.webkit.** { *; }
-dontwarn androidx.webkit.**

# ── Share Plus ────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# ── Image / Camera ────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# ── Kotlin & Coroutines ───────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-dontwarn kotlin.**
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ── Prevent stripping of reflection-based classes ────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ── OkHttp / Okio (used by many plugins) ─────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
