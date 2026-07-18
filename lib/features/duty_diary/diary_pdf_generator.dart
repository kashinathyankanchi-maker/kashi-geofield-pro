import 'dart:io';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text, Colors;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'models/duty_diary_model.dart';

/// Generates the weekly duty diary PDF using HTML → PDF conversion.
///
/// WHY HTML-based approach instead of pw.Document?
/// The `pdf` Dart package performs simple glyph lookup from TTF files but
/// does NOT support OpenType GSUB/GPOS layout features required by Kannada
/// (conjunct consonants, matras, half-forms).
///
/// `Printing.convertHtml()` uses Android's system WebView / iOS WKWebView
/// which natively handles complex Indic script shaping — so BOTH Kannada
/// and English render perfectly with no additional fonts needed.
class DiaryPdfGenerator {
  static Future<void> generateWeeklyPdf(
    BuildContext context,
    DateTime startOfWeek,
    List<DutyDiaryModel> entries,
  ) async {
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    // Build day → entry map (0 = Mon … 6 = Sun)
    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      final dt = DateTime.parse(e.date);
      weekData[dt.weekday - 1] = e;
    }

    // Build HTML content
    final html = _buildHtml(startOfWeek, endOfWeek, weekData);

    try {
      // Convert HTML → PDF bytes using Android/iOS system rendering engine.
      // This properly handles Kannada complex script shaping via native WebView.
      final bytes = await Printing.convertHtml(
        format: PdfPageFormat.a4,
        html: html,
      );

      final downloadDir = Directory('/storage/emulated/0/Download');
      File file;
      bool savedToDownloads = false;

      if (downloadDir.existsSync()) {
        try {
          file = File(
              '${downloadDir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
          await file.writeAsBytes(bytes);
          savedToDownloads = true;
        } catch (_) {
          final dir = await getApplicationDocumentsDirectory();
          file = File(
              '${dir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
          await file.writeAsBytes(bytes);
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        file = File('${dir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
        await file.writeAsBytes(bytes);
      }

      // ignore: use_build_context_synchronously
      if (context.mounted && savedToDownloads) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF saved to Downloads!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await Share.shareXFiles([XFile(file.path)],
          text: 'Weekly Duty Diary PDF');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
      }
    }
  }

  // ── HTML builder ──────────────────────────────────────────────────────────
  static String _buildHtml(
    DateTime startOfWeek,
    DateTime endOfWeek,
    Map<int, DutyDiaryModel> weekData,
  ) {
    final rowsBuffer = StringBuffer();
    for (int i = 0; i < 7; i++) {
      final date = startOfWeek.add(Duration(days: i));
      final entry = weekData[i];
      final dayName = DateFormat('EEEE').format(date);
      final dateStr = DateFormat('dd/MM/yyyy').format(date);
      final locations = _e(entry?.locations ?? '');
      final activities = _e(entry?.activities ?? '');
      final dist =
          entry != null ? entry.distance.toStringAsFixed(1) : '';

      rowsBuffer.write('''
        <tr>
          <td class="day-cell">
            <strong>$dayName</strong><br>
            <span class="date-label">$dateStr</span>
          </td>
          <td class="data-cell">$locations</td>
          <td class="data-cell">$activities</td>
          <td class="dist-cell">$dist</td>
        </tr>
      ''');
    }

    final weekLabel =
        '${DateFormat('MMM d, yyyy').format(startOfWeek)} &nbsp;To:&nbsp; '
        '${DateFormat('MMM d, yyyy').format(endOfWeek)}';

    return '''<!DOCTYPE html>
<html lang="kn">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Weekly Duty Diary</title>
  <style>
    /* System fonts used — Android/iOS has built-in Kannada support */
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: sans-serif;
      font-size: 11px;
      color: #000;
      padding: 24px;
    }
    h1 {
      text-align: center;
      color: #2e5b2c;
      font-size: 18px;
      font-weight: bold;
      margin-bottom: 4px;
    }
    .subtitle {
      text-align: center;
      color: #666;
      font-size: 11px;
      margin-bottom: 12px;
    }
    hr.green {
      border: none;
      border-top: 2px solid #2e5b2c;
      margin-bottom: 10px;
    }
    .info-row {
      display: flex;
      justify-content: space-between;
      font-size: 10px;
      margin-bottom: 4px;
    }
    .info-label { font-style: italic; }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 12px;
    }
    th {
      background-color: #e8f5e9;
      color: #1b5e20;
      font-weight: bold;
      font-size: 10px;
      border: 1px solid #aaa;
      padding: 6px;
      text-align: center;
    }
    td {
      border: 1px solid #aaa;
      padding: 5px 6px;
      vertical-align: top;
      font-size: 11px;
      /* Uses system default font which includes Kannada on Android/iOS */
    }
    .day-cell {
      background-color: #f1f8e9;
      width: 90px;
      font-size: 10px;
    }
    .date-label { color: #666; font-size: 9px; }
    .data-cell {
      /* no special font needed — system handles Kannada natively */
    }
    .dist-cell { text-align: center; width: 45px; }
    .summary-box {
      border: 1px solid #888;
      min-height: 80px;
      padding: 8px;
      margin-top: 14px;
      font-weight: bold;
      color: #2e5b2c;
      font-size: 11px;
    }
    .sig-row {
      display: flex;
      justify-content: space-between;
      margin-top: 50px;
    }
    .sig-block { text-align: center; font-size: 10px; }
    .sig-line {
      border-top: 1px solid #000;
      margin-bottom: 4px;
    }
    .sig-block-left .sig-line { width: 160px; }
    .sig-block-right .sig-line { width: 220px; }
  </style>
</head>
<body>
  <h1>WEEKLY DUTY DIARY</h1>
  <p class="subtitle">Forest Department Official Log</p>
  <hr class="green">

  <div class="info-row">
    <span>Week Of: $weekLabel</span>
    <span class="info-label">Officer Name: _____________________</span>
  </div>
  <div class="info-row">
    <span class="info-label">Section / Beat: ___________________</span>
    <span class="info-label">Range: ___________________________</span>
  </div>

  <table>
    <thead>
      <tr>
        <th>Day</th>
        <th>Locations / Compartments</th>
        <th>Key Activities &amp; Observations<br>(Wildlife, Offenses, Flora)</th>
        <th>Dist<br>(km)</th>
      </tr>
    </thead>
    <tbody>
      ${rowsBuffer.toString()}
    </tbody>
  </table>

  <div class="summary-box">Weekly Summary &amp; Notes</div>

  <div class="sig-row">
    <div class="sig-block sig-block-left">
      <div class="sig-line"></div>
      Signature of the Officer
    </div>
    <div class="sig-block sig-block-right">
      <div class="sig-line"></div>
      Signature of the Supervising Officer (RFO)
    </div>
  </div>
</body>
</html>''';
  }

  /// HTML-escape special characters so user text renders safely in HTML
  static String _e(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll('\n', '<br>');
  }

  // ── CSV Export (unchanged) ────────────────────────────────────────────────
  static Future<void> generateWeeklyCsv(
    BuildContext context,
    DateTime startOfWeek,
    List<DutyDiaryModel> entries,
  ) async {
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      final dt = DateTime.parse(e.date);
      weekData[dt.weekday - 1] = e;
    }

    final csv = StringBuffer();
    csv.writeln('WEEKLY DUTY DIARY');
    csv.writeln(
        'Week Of: ${df.format(startOfWeek)} To: ${df.format(endOfWeek)}');
    csv.writeln();
    csv.writeln(
        'Day,Date,Locations/Compartments,Activities & Observations,Distance (km)');

    for (int i = 0; i < 7; i++) {
      final currentDay = startOfWeek.add(Duration(days: i));
      final dayName = DateFormat('EEEE').format(currentDay);
      final dateStr = df.format(currentDay);
      final entry = weekData[i];

      final loc = entry?.locations
              .replaceAll('"', '""')
              .replaceAll('\n', ' ') ??
          '';
      final act = entry?.activities
              .replaceAll('"', '""')
              .replaceAll('\n', ' ') ??
          '';
      final dist =
          entry != null ? entry.distance.toStringAsFixed(1) : '';

      csv.writeln('"$dayName","$dateStr","$loc","$act","$dist"');
    }

    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      File file;
      bool savedToDownloads = false;

      if (downloadDir.existsSync()) {
        try {
          file = File(
              '${downloadDir.path}/Duty_Diary_${df.format(startOfWeek)}.csv');
          await file.writeAsString(csv.toString());
          savedToDownloads = true;
        } catch (_) {
          final dir = await getApplicationDocumentsDirectory();
          file = File(
              '${dir.path}/Duty_Diary_${df.format(startOfWeek)}.csv');
          await file.writeAsString(csv.toString());
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        file =
            File('${dir.path}/Duty_Diary_${df.format(startOfWeek)}.csv');
        await file.writeAsString(csv.toString());
      }

      // ignore: use_build_context_synchronously
      if (context.mounted && savedToDownloads) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CSV saved to Downloads!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await Share.shareXFiles([XFile(file.path)],
          text: 'Weekly Duty Diary CSV');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
