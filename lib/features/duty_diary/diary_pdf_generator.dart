import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text, Colors;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../core/utils/storage_helper.dart';
import 'models/duty_diary_model.dart';

/// How Kannada is rendered correctly:
/// ─────────────────────────────────
/// The `pdf` Dart package only does simple glyph lookup and does NOT support
/// OpenType GSUB/GPOS layout — which Kannada needs for conjuncts like ಕ್ಷ, ಜ್ಞ.
///
/// Fix: we render each user-typed text cell as a PNG image using [dart:ui]
/// (Flutter's native low-level canvas). This uses the device's built-in text
/// shaping engine, so ALL Kannada characters — including complex conjuncts and
/// vowel marks — are rendered pixel-perfectly.  The images are then embedded
/// into the `pw.Document` as `pw.MemoryImage` cells.
class DiaryPdfGenerator {
  // ── Column widths in PDF points ──────────────────────────────────────────
  // A4 = 595.28pt. Margins = 32pt × 2 = 64pt. Table = 531pt.
  // Day = 80pt, Dist = 50pt → remaining = 401pt
  // Locations = 401 × 2/5 = 160pt, Activities = 401 × 3/5 = 241pt
  static const double _colLoc = 160;
  static const double _colAct = 241;
  static const double _cellPad = 6; // padding inside each cell (pt)
  static const double _imgW_loc = _colLoc - _cellPad * 2;
  static const double _imgW_act = _colAct - _cellPad * 2;
  static const double _dpr = 2.5; // render at 2.5× for crisp text in PDF
  static const double _fontSize = 10.0;

  static Future<void> generateWeeklyPdf(
    BuildContext context,
    DateTime startOfWeek,
    List<DutyDiaryModel> entries,
  ) async {
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    // Map weekday → entry
    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      weekData[DateTime.parse(e.date).weekday - 1] = e;
    }

    // ── Pre-render all Kannada/English text cells as PNG images ─────────────
    // This uses Flutter's native dart:ui rendering — correct Kannada shaping.
    final List<_PreRendered> rendered = [];
    for (int i = 0; i < 7; i++) {
      final entry = weekData[i];
      final locBytes =
          await _renderText(entry?.locations ?? '', _imgW_loc);
      final actBytes =
          await _renderText(entry?.activities ?? '', _imgW_act);
      rendered.add(_PreRendered(locBytes: locBytes, actBytes: actBytes));
    }

    // ── Build PDF ────────────────────────────────────────────────────────────
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          final weekLabel =
              '${DateFormat('MMM d, yyyy').format(startOfWeek)}'
              '  To:  ${DateFormat('MMM d, yyyy').format(endOfWeek)}';

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Center(
                child: pw.Text(
                  'WEEKLY DUTY DIARY',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#2e5b2c'),
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text('Forest Department Official Log',
                    style: pw.TextStyle(
                        fontSize: 11, color: PdfColors.grey700)),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(
                  color: PdfColor.fromHex('#2e5b2c'), thickness: 1.5),
              pw.SizedBox(height: 8),

              // Week info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Week Of: $weekLabel',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Officer Name: _____________________',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Section / Beat: ___________________',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Range: ___________________________',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 12),

              // Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey500),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FixedColumnWidth(50),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#e8f5e9')),
                    children: [
                      _hCell('Day'),
                      _hCell('Locations /\nCompartments'),
                      _hCell(
                          'Key Activities & Observations\n(Wildlife, Offences, Flora)'),
                      _hCell('Dist\n(km)'),
                    ],
                  ),
                  // Data rows
                  for (int i = 0; i < 7; i++)
                    _buildRow(
                      startOfWeek.add(Duration(days: i)),
                      weekData[i],
                      rendered[i],
                    ),
                ],
              ),

              pw.SizedBox(height: 14),

              // Summary box
              pw.Container(
                height: 80,
                width: double.infinity,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey600)),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  'Weekly Summary & Notes',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#2e5b2c'),
                    fontSize: 11,
                  ),
                ),
              ),

              pw.Spacer(),
              pw.Divider(color: PdfColors.black, thickness: 1.5),
              pw.SizedBox(height: 36),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(children: [
                    pw.Container(
                        width: 150, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Signature of the Officer',
                        style: const pw.TextStyle(fontSize: 10)),
                  ]),
                  pw.Column(children: [
                    pw.Container(
                        width: 210, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Signature of the Supervising Officer',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('(RFO)',
                        style: const pw.TextStyle(fontSize: 10)),
                  ]),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ── Save & share ─────────────────────────────────────────────────────────
    try {
      final bytes = await pdf.save();
      final folderPath = await StorageHelper.getAppStorageDirectory();
      final file = File('$folderPath/Duty_Diary_${df.format(startOfWeek)}.pdf');
      await file.writeAsBytes(bytes);
      
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PDF saved to Kashi GeoField Pro folder!'),
              backgroundColor: Colors.green),
        );
      }
      await Share.shareXFiles([XFile(file.path)],
          text: 'Weekly Duty Diary PDF');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF error: $e')));
      }
    }
  }

  // ── Render text → PNG bytes using dart:ui (handles Kannada shaping) ───────
  static Future<Uint8List?> _renderText(String text, double widthPt) async {
    if (text.trim().isEmpty) return null;

    final pxW = (widthPt * _dpr).round();
    final pxFontSize = _fontSize * _dpr;
    final pxPad = 4.0 * _dpr;

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        fontSize: pxFontSize,
        height: 1.45,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xFF000000),
        // Use NotoSansKannada which is registered in pubspec.yaml.
        // dart:ui respects font assets declared in Flutter and applies
        // the full ICU/HarfBuzz text shaping pipeline — so Kannada
        // conjuncts, matras, and ligatures all render correctly.
        fontFamily: 'NotoSansKannada',
        fontSize: pxFontSize,
      ))
      ..addText(text);

    final para = builder.build()
      ..layout(ui.ParagraphConstraints(width: pxW.toDouble()));

    final pxH = (para.height + pxPad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // White background
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(para, ui.Offset(0, pxPad));
    final picture = recorder.endRecording();

    final img = await picture.toImage(pxW, pxH);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  }

  // ── Build one table data row ───────────────────────────────────────────────
  static pw.TableRow _buildRow(
    DateTime date,
    DutyDiaryModel? entry,
    _PreRendered pre,
  ) {
    final dayName = DateFormat('EEEE').format(date);
    final dateStr = DateFormat('dd/MM').format(date);

    return pw.TableRow(children: [
      // Day column — pure English text, built-in font is fine
      pw.Container(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        color: PdfColor.fromHex('#f1f8e9'),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(dayName,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 6),
            pw.Text('Date: $dateStr',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      ),

      // Locations — image rendered by dart:ui
      _imageCell(pre.locBytes, _imgW_loc),

      // Activities — image rendered by dart:ui
      _imageCell(pre.actBytes, _imgW_act),

      // Distance — numeric, English only
      pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Center(
          child: pw.Text(
            entry != null ? entry.distance.toStringAsFixed(1) : '',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ),
    ]);
  }

  /// Returns a cell containing the pre-rendered image, or an empty cell.
  static pw.Widget _imageCell(Uint8List? bytes, double widthPt) {
    if (bytes == null) {
      return pw.Padding(
          padding: pw.EdgeInsets.all(_cellPad), child: pw.SizedBox());
    }
    return pw.Padding(
      padding: pw.EdgeInsets.all(_cellPad),
      child: pw.Image(
        pw.MemoryImage(bytes),
        width: widthPt,
        // height is derived from the image aspect ratio automatically
      ),
    );
  }

  // ── Header cell ───────────────────────────────────────────────────────────
  static pw.Widget _hCell(String text) => pw.Padding(
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

  // ── CSV Export ─────────────────────────────────────────────────────────────
  static Future<void> generateWeeklyCsv(
    BuildContext context,
    DateTime startOfWeek,
    List<DutyDiaryModel> entries,
  ) async {
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');

    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      weekData[DateTime.parse(e.date).weekday - 1] = e;
    }

    final csv = StringBuffer();
    csv.writeln('WEEKLY DUTY DIARY');
    csv.writeln(
        'Week Of: ${df.format(startOfWeek)} To: ${df.format(endOfWeek)}');
    csv.writeln();
    csv.writeln(
        'Day,Date,Locations/Compartments,Activities & Observations,Distance (km)');

    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      final entry = weekData[i];
      final loc =
          (entry?.locations ?? '').replaceAll('"', '""').replaceAll('\n', ' ');
      final act =
          (entry?.activities ?? '').replaceAll('"', '""').replaceAll('\n', ' ');
      final dist = entry != null ? entry.distance.toStringAsFixed(1) : '';
      csv.writeln(
          '"${DateFormat('EEEE').format(day)}","${df.format(day)}","$loc","$act","$dist"');
    }

    try {
      final folderPath = await StorageHelper.getAppStorageDirectory();
      final file = File('$folderPath/Duty_Diary_${df.format(startOfWeek)}.csv');
      await file.writeAsString(csv.toString());
      
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('CSV saved to Kashi GeoField Pro folder!'),
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

// ── Helper data class ──────────────────────────────────────────────────────
class _PreRendered {
  final Uint8List? locBytes;
  final Uint8List? actBytes;
  const _PreRendered({this.locBytes, this.actBytes});
}
