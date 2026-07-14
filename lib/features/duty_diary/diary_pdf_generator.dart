import 'dart:io';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text, Colors;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'models/duty_diary_model.dart';

class DiaryPdfGenerator {
  static Future<void> generateWeeklyPdf(
      BuildContext context,
      DateTime startOfWeek,
      List<DutyDiaryModel> entries) async {
    final pdf = pw.Document();
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    // ── Load Kannada font (used ONLY for user-typed data) ──────────────────
    pw.Font? kannadaFont;
    try {
      final fontData =
          await rootBundle.load('assets/fonts/NotoSansKannada-Regular.ttf');
      kannadaFont = pw.Font.ttf(fontData);
    } catch (_) {
      // fall back to default if font fails
    }

    // Helper: style for user-entered data (Kannada or English)
    pw.TextStyle dataStyle({double fontSize = 10}) => pw.TextStyle(
          font: kannadaFont,
          fontSize: fontSize,
        );

    // Helper: style for static English labels (uses built-in PDF font)
    pw.TextStyle labelStyle({
      double fontSize = 10,
      pw.FontWeight fontWeight = pw.FontWeight.normal,
      PdfColor? color,
    }) =>
        pw.TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        );

    // Build day → entry map (0=Mon … 6=Sun)
    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      final dt = DateTime.parse(e.date);
      weekData[dt.weekday - 1] = e;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── Header title ───────────────────────────────────────────────
              pw.Center(
                child: pw.Text(
                  'WEEKLY DUTY DIARY',
                  style: labelStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#2e5b2c'),
                  ),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  'Forest Department Official Log',
                  style: labelStyle(
                      fontSize: 11, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(
                  color: PdfColor.fromHex('#2e5b2c'), thickness: 1.5),
              pw.SizedBox(height: 10),

              // ── Week / Officer info ────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Week Of: ${DateFormat('MMM d, yyyy').format(startOfWeek)}'
                    ' To: ${DateFormat('MMM d, yyyy').format(endOfWeek)}',
                    style: labelStyle(fontSize: 10),
                  ),
                  pw.Text('Officer Name: _____________________',
                      style: labelStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Section / Beat: ___________________',
                      style: labelStyle(fontSize: 10)),
                  pw.Text('Range: ___________________________',
                      style: labelStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 12),

              // ── Table ──────────────────────────────────────────────────────
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FixedColumnWidth(50),
                },
                children: [
                  // Header row — all English labels, default font
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#e8f5e9')),
                    children: [
                      _headerCell('Day'),
                      _headerCell('Locations /\nCompartments'),
                      _headerCell(
                          'Key Activities & Observations\n(Wildlife, Offenses, Flora)'),
                      _headerCell('Dist\n(km)'),
                    ],
                  ),
                  // Data rows Mon–Sun
                  for (int i = 0; i < 7; i++)
                    _dataRow(
                      startOfWeek.add(Duration(days: i)),
                      weekData[i],
                      dataStyle,
                    ),
                ],
              ),

              pw.SizedBox(height: 16),

              // ── Summary box ────────────────────────────────────────────────
              pw.Container(
                height: 80,
                width: double.infinity,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey600)),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  'Weekly Summary & Notes',
                  style: labelStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#2e5b2c'),
                  ),
                ),
              ),

              pw.Spacer(),
              pw.Divider(color: PdfColors.black, thickness: 1.5),
              pw.SizedBox(height: 40),

              // ── Signatures ─────────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(children: [
                    pw.Container(
                        width: 150, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Signature of the Officer',
                        style: labelStyle(fontSize: 10)),
                  ]),
                  pw.Column(children: [
                    pw.Container(
                        width: 200, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Signature of the Supervising Officer',
                        style: labelStyle(fontSize: 10)),
                    pw.Text('(RFO)', style: labelStyle(fontSize: 10)),
                  ]),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ── Save & Share ──────────────────────────────────────────────────────
    try {
      final bytes = await pdf.save();
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
        file =
            File('${dir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
        await file.writeAsBytes(bytes);
      }

      // ignore: use_build_context_synchronously
      if (context.mounted && savedToDownloads) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PDF saved to Downloads!'),
              backgroundColor: Colors.green),
        );
      }
      await Share.shareXFiles([XFile(file.path)],
          text: 'Weekly Duty Diary PDF');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Static English header cell (built-in PDF font) ──────────────────────
  static pw.Widget _headerCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Center(
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#1b5e20'),
          ),
        ),
      ),
    );
  }

  // ── Data row: English labels + Kannada-aware user data ──────────────────
  static pw.TableRow _dataRow(
    DateTime date,
    DutyDiaryModel? entry,
    pw.TextStyle Function({double fontSize}) dataStyle,
  ) {
    // Day name & date use default English font
    final dayName = DateFormat('EEEE').format(date);
    final dateStr = DateFormat('dd/MM').format(date);

    return pw.TableRow(
      children: [
        // Day column — English label
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          color: PdfColor.fromHex('#f1f8e9'),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(dayName,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.SizedBox(height: 8),
              pw.Text('Date: $dateStr',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
        ),
        // Locations — user typed (may be Kannada)
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            entry?.locations ?? '',
            style: dataStyle(fontSize: 10),
          ),
        ),
        // Activities — user typed (may be Kannada)
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            entry?.activities ?? '',
            style: dataStyle(fontSize: 10),
          ),
        ),
        // Distance — number, default font
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Center(
            child: pw.Text(
              entry != null ? entry.distance.toStringAsFixed(1) : '',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  // ── CSV Export ───────────────────────────────────────────────────────────
  static Future<void> generateWeeklyCsv(
      BuildContext context,
      DateTime startOfWeek,
      List<DutyDiaryModel> entries) async {
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

      final loc =
          entry?.locations.replaceAll('"', '""').replaceAll('\n', ' ') ??
              '';
      final act =
          entry?.activities.replaceAll('"', '""').replaceAll('\n', ' ') ??
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
              backgroundColor: Colors.green),
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
