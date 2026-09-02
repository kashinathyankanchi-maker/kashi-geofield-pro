import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text, Colors;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../core/utils/storage_helper.dart';
import 'models/duty_diary_model.dart';

/// Renders the official Karnataka Forest Department
/// Weekly Duty Diary in the Kannada format exactly as shown
/// in the printed form.
///
/// Kannada text is rendered as PNG images via [dart:ui] so that
/// the device's full HarfBuzz shaping pipeline is used — giving
/// correct conjuncts, matras and ligatures that the `pdf` package
/// cannot produce on its own.
class DiaryPdfGenerator {
  // ── Column widths (A4 = 595pt, margins 28pt each = 539pt usable) ─────────
  static const double _colDay   = 55;   // ವಾರ/ದಿನಾಂಕ
  static const double _colCamp  = 70;   // ಕೇಂದ್ರ,ಸ್ಥಾನ
  static const double _colDep   = 42;   // ಹೊರಟ ವೇಳೆ
  static const double _colPlace = 110;  // ತಿರುಗಾಡಿದ ಸ್ಥಳ
  static const double _colRet   = 42;   // ಹಿಂತಿರುಗಿದ ವೇಳೆ
  static const double _colMode  = 65;   // ರೀತಿ & ಕಿ.ಮೀ
  static const double _colWork  = 155;  // ಕೆಲಸ ಮಾಡಿದ ವಿವರ

  static const double _cellPad  = 4;
  static const double _dpr      = 2.5;   // render at 2.5× for crisp text
  static const double _fontSize = 9.5;

  static Future<void> generateWeeklyPdf(
    BuildContext context,
    DateTime startOfWeek,
    List<DutyDiaryModel> entries, {
    String officerName   = '',
    String subDivision   = '',
    String range         = '',
    String division      = '',
    int    weekNumber    = 0,
    String month        = '',
    int    year         = 0,
  }) async {
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final df = DateFormat('yyyy-MM-dd');
    final ddMM = DateFormat('dd/MM/yyyy');

    // Map weekday index (0=Mon … 6=Sun) → entry
    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      final d = DateTime.tryParse(e.date);
      if (d != null) weekData[d.weekday - 1] = e;
    }

    // ── Pre-render all Kannada text cells as PNG via dart:ui ────────────────
    final pre = <_PreRendered>[];
    for (int i = 0; i < 7; i++) {
      final e = weekData[i];
      pre.add(_PreRendered(
        campBytes:  await _renderText(e?.campStation   ?? '', _colCamp  - _cellPad * 2),
        placeBytes: await _renderText(e?.placesVisited ?? '', _colPlace - _cellPad * 2),
        modeBytes:  await _renderText(e?.modeAndKm    ?? '', _colMode  - _cellPad * 2),
        workBytes:  await _renderText(e?.workDone     ?? '', _colWork  - _cellPad * 2),
      ));
    }

    // ── Build PDF ────────────────────────────────────────────────────────────
    final pdf = pw.Document();
    final wn  = weekNumber > 0 ? weekNumber : _isoWeek(startOfWeek);
    final yr  = year > 0 ? year : startOfWeek.year;
    final mn  = month.isNotEmpty ? month : DateFormat('MMMM').format(startOfWeek);
    final rfo = officerName.isNotEmpty ? officerName : '_' * 20;
    final sd  = subDivision.isNotEmpty ? subDivision : '_' * 20;
    final rng = range.isNotEmpty      ? range        : '_' * 20;
    final div = division.isNotEmpty   ? division     : '_' * 20;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ── Line 1: Officer / Sub-division / Range / Division ───────────
            pw.Row(children: [
              pw.Text('ಶ್ರೀ ', style: _s(10)),
              pw.Text(rfo, style: _sb(10)),
              pw.Spacer(),
              pw.Text(' ಉಪವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ. ', style: _s(10)),
              pw.Text(sd, style: _sb(10)),
              pw.Spacer(),
              pw.Text(' ವಲಯ ', style: _s(10)),
              pw.Text(rng, style: _sb(10)),
              pw.Spacer(),
              pw.Text(' ವಿಭಾಗ', style: _s(10)),
            ]),
            pw.SizedBox(height: 5),

            // ── Line 2: Year / Month / Dates / Week number ─────────────────
            pw.Row(children: [
              pw.Text('ಇವರ ', style: _s(9)),
              pw.Text('$yr', style: _sb(9)),
              pw.Text('ನೇ ಸಾಲಿನ ', style: _s(9)),
              pw.Text(mn, style: _sb(9)),
              pw.Text(' ತಿಂಗಳ ದಿನಾಂಕ ', style: _s(9)),
              pw.Text(ddMM.format(startOfWeek), style: _sb(9)),
              pw.Text(' ರಿಂದ ', style: _s(9)),
              pw.Text(ddMM.format(endOfWeek), style: _sb(9)),
              pw.Text(' ರವರೆಗಿನ ', style: _s(9)),
              pw.Text('$wn', style: _sb(9)),
              pw.Text(' ನೇ ವಾರದ ದಿನಚರಿ ಯಾದಿ.', style: _s(9)),
            ]),
            pw.SizedBox(height: 8),

            // ── Table ───────────────────────────────────────────────────────
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
              columnWidths: {
                0: pw.FixedColumnWidth(_colDay),
                1: pw.FixedColumnWidth(_colCamp),
                2: pw.FixedColumnWidth(_colDep),
                3: pw.FixedColumnWidth(_colPlace),
                4: pw.FixedColumnWidth(_colRet),
                5: pw.FixedColumnWidth(_colMode),
                6: pw.FixedColumnWidth(_colWork),
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#f5f5f5')),
                  children: [
                    _hCell('ವಾರ/ದಿನಾಂಕ'),
                    _hCell('ಕೇಂದ್ರ, ಸ್ಥಾನ\n(ಮುಕ್ಕಾಂ)'),
                    _hCell('ಹೊರಟ\nವೇಳೆ'),
                    _hCell('ತಿರುಗಾಡಿದ ಸ್ಥಳ'),
                    _hCell('ಹಿಂತಿರುಗಿದ\nವೇಳೆ'),
                    _hCell('ತಿರುಗಾಡಿದ\nರೀತಿ & ಕಿ.ಮೀ'),
                    _hCell('ಕೆಲಸ ಮಾಡಿದ ವಿವರ'),
                  ],
                ),
                // 7 data rows (Mon … Sun)
                for (int i = 0; i < 7; i++)
                  _buildRow(startOfWeek.add(Duration(days: i)), weekData[i], pre[i]),
              ],
            ),
            pw.SizedBox(height: 14),

            // ── Footer ──────────────────────────────────────────────────────
            pw.Row(children: [
              pw.Text('ಮಾನ್ಯ ವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿಗಳು ', style: _s(9)),
              pw.Text(rng, style: _sb(9)),
              pw.Text(' ರವರಿಗೆ ಗೌರವಪೂರ್ವಕವಾಗಿ ಒಪ್ಪಿಸಿದೆ.', style: _s(9)),
              pw.Spacer(),
              pw.Text('ಸಹಿ', style: _s(9)),
            ]),
            pw.SizedBox(height: 30),

            // ── Signature line ──────────────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(width: 180, height: 1, color: PdfColors.black),
              ],
            ),
          ],
        ),
      ),
    );

    // ── Save & share ─────────────────────────────────────────────────────────
    try {
      final bytes      = await pdf.save();
      final folderPath = await StorageHelper.getAppStorageDirectory();
      final file       = File('$folderPath/Duty_Diary_${df.format(startOfWeek)}.pdf');
      await file.writeAsBytes(bytes);

      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF saved to Kashi GeoField Pro folder!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await Share.shareXFiles([XFile(file.path)], text: 'Weekly Duty Diary PDF');
    } catch (e) {
      // ignore: use_build_context_synchronously
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF error: $e')));
      }
    }
  }

  // ── Render Kannada/English text → PNG bytes ──────────────────────────────
  static Future<Uint8List?> _renderText(String text, double widthPt) async {
    if (text.trim().isEmpty) return null;
    final pxW        = (widthPt * _dpr).round();
    final pxFontSize = _fontSize * _dpr;
    final pxPad      = 3.0 * _dpr;

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        fontSize: pxFontSize,
        height: 1.4,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xFF000000),
        fontFamily: 'NotoSansKannada',
        fontSize: pxFontSize,
      ))
      ..addText(text);

    final para = builder.build()
      ..layout(ui.ParagraphConstraints(width: pxW.toDouble()));
    final pxH = (para.height + pxPad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas   = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(para, ui.Offset(0, pxPad));
    final picture = recorder.endRecording();
    final img     = await picture.toImage(pxW, pxH);
    final bd      = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  }

  // ── Build one data row ───────────────────────────────────────────────────
  static pw.TableRow _buildRow(
    DateTime date,
    DutyDiaryModel? entry,
    _PreRendered pre,
  ) {
    final dayNames = ['ಸೋಮ', 'ಮಂಗಳ', 'ಬುಧ', 'ಗುರು', 'ಶುಕ್ರ', 'ಶನಿ', 'ಭಾನು'];
    final dayKn   = dayNames[date.weekday - 1];
    final dateStr = DateFormat('dd/MM').format(date);
    final dep     = entry?.departureTime ?? '';
    final ret     = entry?.returnTime    ?? '';

    return pw.TableRow(children: [
      // Col 1 ─ ವಾರ/ದಿನಾಂಕ
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(dayKn,   style: _sb(9), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 2),
            pw.Text(dateStr, style: _s(8),  textAlign: pw.TextAlign.center),
          ],
        ),
      ),
      // Col 2 ─ ಕೇಂದ್ರ,ಸ್ಥಾನ (image)
      _imgCell(pre.campBytes,  _colCamp  - _cellPad * 2),
      // Col 3 ─ ಹೊರಟ ವೇಳೆ (plain text — usually digits)
      pw.Padding(
        padding: pw.EdgeInsets.all(_cellPad),
        child: pw.Center(child: pw.Text(dep, style: _s(9))),
      ),
      // Col 4 ─ ತಿರುಗಾಡಿದ ಸ್ಥಳ (image)
      _imgCell(pre.placeBytes, _colPlace - _cellPad * 2),
      // Col 5 ─ ಹಿಂತಿರುಗಿದ ವೇಳೆ
      pw.Padding(
        padding: pw.EdgeInsets.all(_cellPad),
        child: pw.Center(child: pw.Text(ret, style: _s(9))),
      ),
      // Col 6 ─ ರೀತಿ & ಕಿ.ಮೀ (image)
      _imgCell(pre.modeBytes,  _colMode  - _cellPad * 2),
      // Col 7 ─ ಕೆಲಸ ಮಾಡಿದ ವಿವರ (image)
      _imgCell(pre.workBytes,  _colWork  - _cellPad * 2),
    ]);
  }

  // ── Image cell helper ────────────────────────────────────────────────────
  static pw.Widget _imgCell(Uint8List? bytes, double widthPt) {
    if (bytes == null) {
      return pw.Padding(
          padding: pw.EdgeInsets.all(_cellPad),
          child: pw.SizedBox(height: 30));
    }
    return pw.Padding(
      padding: pw.EdgeInsets.all(_cellPad),
      child: pw.Image(pw.MemoryImage(bytes), width: widthPt),
    );
  }

  // ── Header cell helper ────────────────────────────────────────────────────
  static pw.Widget _hCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: pw.Center(
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );

  // ── Text style helpers ────────────────────────────────────────────────────
  static pw.TextStyle _s(double size) => pw.TextStyle(fontSize: size);
  static pw.TextStyle _sb(double size) =>
      pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold);

  // ── ISO week number ───────────────────────────────────────────────────────
  static int _isoWeek(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return ((date.difference(startOfYear).inDays) / 7).floor() + 1;
  }

  // ── CSV Export ─────────────────────────────────────────────────────────────
  static Future<void> generateWeeklyCsv(
    BuildContext context,
    DateTime startOfWeek,
    List<DutyDiaryModel> entries,
  ) async {
    final df  = DateFormat('yyyy-MM-dd');
    final ddMM = DateFormat('dd/MM/yyyy');
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      final d = DateTime.tryParse(e.date);
      if (d != null) weekData[d.weekday - 1] = e;
    }

    final csv = StringBuffer();
    csv.writeln('ವಾರದ ದಿನಚರಿ ಯಾದಿ / Weekly Duty Diary');
    csv.writeln('${ddMM.format(startOfWeek)} ರಿಂದ ${ddMM.format(endOfWeek)}');
    csv.writeln();
    csv.writeln('ವಾರ/ದಿನಾಂಕ,ಕೇಂದ್ರ ಸ್ಥಾನ,ಹೊರಟ ವೇಳೆ,ತಿರುಗಾಡಿದ ಸ್ಥಳ,ಹಿಂತಿರುಗಿದ ವೇಳೆ,ರೀತಿ & ಕಿ.ಮೀ,ಕೆಲಸ ಮಾಡಿದ ವಿವರ');

    final dayNames = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    for (int i = 0; i < 7; i++) {
      final day   = startOfWeek.add(Duration(days: i));
      final entry = weekData[i];
      String q(String s) => '"${s.replaceAll('"', '""').replaceAll('\n', ' ')}"';
      csv.writeln('${dayNames[i]} ${ddMM.format(day)},'
          '${q(entry?.campStation   ?? '')},'
          '${q(entry?.departureTime ?? '')},'
          '${q(entry?.placesVisited ?? '')},'
          '${q(entry?.returnTime    ?? '')},'
          '${q(entry?.modeAndKm    ?? '')},'
          '${q(entry?.workDone     ?? '')}');
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
            backgroundColor: Colors.green,
          ),
        );
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

// ── Pre-rendered text images for one diary row ────────────────────────────
class _PreRendered {
  final Uint8List? campBytes;
  final Uint8List? placeBytes;
  final Uint8List? modeBytes;
  final Uint8List? workBytes;
  const _PreRendered({
    this.campBytes,
    this.placeBytes,
    this.modeBytes,
    this.workBytes,
  });
}
