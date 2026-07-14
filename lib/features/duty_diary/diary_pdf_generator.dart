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
      BuildContext context, DateTime startOfWeek, List<DutyDiaryModel> entries) async {
    final pdf = pw.Document();

    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    // ── Load Kannada font ──────────────────────────────────────────────────
    pw.Font? kannadaFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSansKannada-Regular.ttf');
      kannadaFont = pw.Font.ttf(fontData);
    } catch (_) {
      // If font fails to load, fall back to default (text may not render)
    }

    pw.TextStyle kannadaStyle({
      double fontSize = 10,
      pw.FontWeight fontWeight = pw.FontWeight.normal,
      PdfColor? color,
    }) {
      return pw.TextStyle(
        font: kannadaFont,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );
    }

    // Create a map of day index (0-6 for Mon-Sun) to entry
    final Map<int, DutyDiaryModel> weekData = {};
    for (var e in entries) {
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
              // ── Week info row ──────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Week Of: ${DateFormat('MMM d, yyyy').format(startOfWeek)} To: ${DateFormat('MMM d, yyyy').format(endOfWeek)}',
                    style: kannadaStyle(fontSize: 10),
                  ),
                  pw.Text('Officer Name: _____________________',
                      style: kannadaStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Section / Beat: ___________________',
                      style: kannadaStyle(fontSize: 10)),
                  pw.Text('Range: ___________________________',
                      style: kannadaStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: PdfColor.fromHex('#2e5b2c'), thickness: 1),
              pw.SizedBox(height: 10),

              // ── Table ───────────────────────────────────────────────────────
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FixedColumnWidth(50),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#e8f5e9')),
                    children: [
                      _buildHeaderCell('Day', kannadaFont),
                      _buildHeaderCell('Locations /\nCompartments', kannadaFont),
                      _buildHeaderCell(
                          'Key Activities & Observations\n(Wildlife, Offenses, Flora)',
                          kannadaFont),
                      _buildHeaderCell('Dist\n(km)', kannadaFont),
                    ],
                  ),
                  // Monday to Sunday rows
                  for (int i = 0; i < 7; i++)
                    _buildDayRow(
                      startOfWeek.add(Duration(days: i)),
                      weekData[i],
                      kannadaFont,
                    ),
                ],
              ),

              pw.SizedBox(height: 16),

              // ── Summary & Notes ─────────────────────────────────────────────
              pw.Container(
                height: 80,
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey600),
                ),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  'Summary & Notes',
                  style: kannadaStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#2e5b2c'),
                  ),
                ),
              ),

              pw.Spacer(),
              pw.Divider(color: PdfColors.black, thickness: 1.5),
              pw.SizedBox(height: 40),

              // ── Signatures ──────────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Signature of the Officer',
                          style: kannadaStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 200, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Signature of the Supervising Officer',
                          style: kannadaStyle(fontSize: 10)),
                      pw.Text('(RFO)', style: kannadaStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    try {
      final bytes = await pdf.save();

      // Attempt to save to public Downloads folder first (Android)
      final downloadDir = Directory('/storage/emulated/0/Download');
      File file;
      bool savedToDownloads = false;

      if (downloadDir.existsSync()) {
        try {
          file = File('${downloadDir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
          await file.writeAsBytes(bytes);
          savedToDownloads = true;
        } catch (_) {
          final dir = await getApplicationDocumentsDirectory();
          file = File('${dir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
          await file.writeAsBytes(bytes);
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        file = File('${dir.path}/Duty_Diary_${df.format(startOfWeek)}.pdf');
        await file.writeAsBytes(bytes);
      }

      // ignore: use_build_context_synchronously
      if (context.mounted) {
        if (savedToDownloads) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('PDF saved to Downloads!'),
                backgroundColor: Colors.green),
          );
        }
      }

      await Share.shareXFiles([XFile(file.path)], text: 'Weekly Duty Diary PDF');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static pw.Widget _buildHeaderCell(String text, pw.Font? font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Center(
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: font,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#1b5e20'),
          ),
        ),
      ),
    );
  }

  static pw.TableRow _buildDayRow(
      DateTime date, DutyDiaryModel? entry, pw.Font? font) {
    final dayName = DateFormat('EEEE').format(date);
    final dateStr = DateFormat('dd/MM').format(date);

    return pw.TableRow(
      children: [
        // Day column
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          color: PdfColor.fromHex('#f1f8e9'),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(dayName,
                  style: pw.TextStyle(
                      font: font,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10)),
              pw.SizedBox(height: 10),
              pw.Text('Date: $dateStr',
                  style: pw.TextStyle(
                      font: font,
                      fontSize: 9,
                      color: PdfColors.grey700)),
            ],
          ),
        ),
        // Locations
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            entry?.locations ?? '',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
        ),
        // Activities
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            entry?.activities ?? '',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
        ),
        // Distance
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Center(
            child: pw.Text(
              entry != null ? entry.distance.toStringAsFixed(1) : '',
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  // ── CSV Export ────────────────────────────────────────────────────────────

  static Future<void> generateWeeklyCsv(
      BuildContext context,
      DateTime startOfWeek,
      List<DutyDiaryModel> entries) async {
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    final Map<int, DutyDiaryModel> weekData = {};
    for (var e in entries) {
      final dt = DateTime.parse(e.date);
      weekData[dt.weekday - 1] = e;
    }

    final StringBuffer csv = StringBuffer();
    csv.writeln('Week Of: ${df.format(startOfWeek)} To: ${df.format(endOfWeek)}');
    csv.writeln();
    csv.writeln('Day,Date,Locations/Compartments,Activities & Observations,Distance (km)');

    for (int i = 0; i < 7; i++) {
      final currentDay = startOfWeek.add(Duration(days: i));
      final dayName = DateFormat('EEEE').format(currentDay);
      final dateStr = df.format(currentDay);
      final entry = weekData[i];

      final locations =
          entry?.locations.replaceAll('"', '""').replaceAll('\n', ' ') ?? '';
      final activities =
          entry?.activities.replaceAll('"', '""').replaceAll('\n', ' ') ?? '';
      final distance =
          entry != null ? entry.distance.toStringAsFixed(1) : '';

      csv.writeln('"$dayName","$dateStr","$locations","$activities","$distance"');
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
      if (context.mounted) {
        if (savedToDownloads) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('CSV saved to Downloads!'),
                backgroundColor: Colors.green),
          );
        }
      }

      await Share.shareXFiles([XFile(file.path)], text: 'Weekly Duty Diary CSV');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
