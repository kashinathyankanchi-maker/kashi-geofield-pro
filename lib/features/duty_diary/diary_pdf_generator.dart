import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text, Colors;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../core/utils/storage_helper.dart';
import 'models/duty_diary_model.dart';

/// Renders the official Karnataka Forest Department
/// Weekly Duty Diary in LANDSCAPE format with 100% accurate
/// Kannada text rendering (zero black box / missing glyph errors).
class DiaryPdfGenerator {
  // ── Landscape A4 = 841.89pt width. Margins = 28pt × 2 = 56pt. Usable = 785.89pt ──
  static const double _colDay   = 70;   // ವಾರ/ದಿನಾಂಕ
  static const double _colCamp  = 110;  // ಕೇಂದ್ರ, ಸ್ಥಾನ (ಮುಕ್ಕಾಂ)
  static const double _colDep   = 60;   // ಹೊರಟ ವೇಳೆ
  static const double _colPlace = 180;  // ತಿರುಗಾಡಿದ ಸ್ಥಳ
  static const double _colRet   = 60;   // ಹಿಂತಿರುಗಿದ ವೇಳೆ
  static const double _colMode  = 95;   // ತಿರುಗಾಡಿದ ರೀತಿ & ಕಿ.ಮೀ
  static const double _colWork  = 210;  // ಕೆಲಸ ಮಾಡಿದ ವಿವರ (Total = 785pt)

  static const double _cellPad  = 4;
  static const double _dpr      = 2.5;   // render at 2.5× for high-resolution PNG
  static const double _fontSize = 11.0;

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
    final df   = DateFormat('yyyy-MM-dd');
    final ddMM = DateFormat('dd/MM/yyyy');

    // Map weekday index (0=Mon … 6=Sun) → entry
    final Map<int, DutyDiaryModel> weekData = {};
    for (final e in entries) {
      final d = DateTime.tryParse(e.date);
      if (d != null) weekData[d.weekday - 1] = e;
    }

    final wn  = weekNumber > 0 ? weekNumber : _isoWeek(startOfWeek);
    final yr  = year > 0 ? year : startOfWeek.year;
    final mn  = month.isNotEmpty ? month : DateFormat('MMMM').format(startOfWeek);
    final rfo = officerName.isNotEmpty ? officerName : '______________';
    final sd  = subDivision.isNotEmpty ? subDivision : '______________';
    final rng = range.isNotEmpty      ? range        : '______________';
    final div = division.isNotEmpty   ? division     : '______________';

    // ── Pre-render Header, Table Headers, and Table Content as PNGs via dart:ui ──
    // Using dart:ui guarantees full Kannada complex text shaping (no black box ☒ glyph errors)

    // Header Line 1: ಶ್ರೀ [Officer] ಉಪವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ. [SubDiv] ವಲಯ [Range] ವಿಭಾಗ [Div]
    final headerLine1Bytes = await _renderText(
      'ಶ್ರೀ $rfo         ಉಪವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿ. $sd         ವಲಯ $rng         ವಿಭಾಗ $div',
      785,
      fontSize: 12.0,
      bold: true,
    );

    // Header Line 2: ಇವರ [Year] ನೇ ಸಾಲಿನ [Month] ತಿಂಗಳ ದಿನಾಂಕ [Start] ರಿಂದ [End] ರವರೆಗಿನ [Week] ನೇ ವಾರದ ದಿನಚರಿ ಯಾದಿ.
    final headerLine2Bytes = await _renderText(
      'ಇವರ $yr ನೇ ಸಾಲಿನ  $mn  ತಿಂಗಳ ದಿನಾಂಕ ${ddMM.format(startOfWeek)} ರಿಂದ ${ddMM.format(endOfWeek)} ರವರೆಗಿನ  $wn  ನೇ ವಾರದ ದಿನಚರಿ ಯಾದಿ.',
      785,
      fontSize: 11.5,
      bold: true,
    );

    // Table Header Cells
    final hDayBytes   = await _renderText('ವಾರ/ದಿನಾಂಕ', _colDay - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);
    final hCampBytes  = await _renderText('ಕೇಂದ್ರ, ಸ್ಥಾನ\n(ಮುಕ್ಕಾಂ)', _colCamp - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);
    final hDepBytes   = await _renderText('ಹೊರಟ ವೇಳೆ', _colDep - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);
    final hPlaceBytes = await _renderText('ತಿರುಗಾಡಿದ ಸ್ಥಳ', _colPlace - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);
    final hRetBytes   = await _renderText('ಹಿಂತಿರುಗಿದ ವೇಳೆ', _colRet - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);
    final hModeBytes  = await _renderText('ತಿರುಗಾಡಿದ\nರೀತಿ & ಕಿ.ಮೀ', _colMode - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);
    final hWorkBytes  = await _renderText('ಕೆಲಸ ಮಾಡಿದ ವಿವರ', _colWork - _cellPad * 2, fontSize: 10.5, bold: true, align: ui.TextAlign.center);

    // Data Row pre-renderings
    final dayNames = ['ಸೋಮ', 'ಮಂಗಳ', 'ಬುಧ', 'ಗುರು', 'ಶುಕ್ರ', 'ಶನಿ', 'ಭಾನು'];
    final pre = <_PreRendered>[];

    for (int i = 0; i < 7; i++) {
      final date = startOfWeek.add(Duration(days: i));
      final e    = weekData[i];

      final dayLabel   = '${dayNames[date.weekday - 1]}\n${DateFormat('dd/MM').format(date)}';
      final dayBytes   = await _renderText(dayLabel, _colDay - _cellPad * 2, fontSize: 10.0, align: ui.TextAlign.center);
      final campBytes  = await _renderText(e?.campStation ?? '', _colCamp - _cellPad * 2);
      final depBytes   = await _renderText(e?.departureTime ?? '', _colDep - _cellPad * 2, fontSize: 10.0, align: ui.TextAlign.center);
      final placeBytes = await _renderText(e?.placesVisited ?? '', _colPlace - _cellPad * 2);
      final retBytes   = await _renderText(e?.returnTime ?? '', _colRet - _cellPad * 2, fontSize: 10.0, align: ui.TextAlign.center);
      final modeBytes  = await _renderText(e?.modeAndKm ?? '', _colMode - _cellPad * 2);
      final workBytes  = await _renderText(e?.workDone ?? '', _colWork - _cellPad * 2);

      pre.add(_PreRendered(
        dayBytes:   dayBytes,
        campBytes:  campBytes,
        depBytes:   depBytes,
        placeBytes: placeBytes,
        retBytes:   retBytes,
        modeBytes:  modeBytes,
        workBytes:  workBytes,
      ));
    }

    // Footer Text: ಮಾನ್ಯ ವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿಗಳು [Range] ರವರಿಗೆ ಗೌರವಪೂರ್ವಕವಾಗಿ ಒಪ್ಪಿಸಿದೆ.
    final footerBytes = await _renderText(
      'ಮಾನ್ಯ ವಲಯ ಅರಣ್ಯಾಧಿಕಾರಿಗಳು $rng ರವರಿಗೆ ಗೌರವಪೂರ್ವಕವಾಗಿ ಒಪ್ಪಿಸಿದೆ.',
      550,
      fontSize: 11.0,
      bold: true,
    );

    // Signature label: ಸಹಿ
    final signBytes = await _renderText(
      'ಸಹಿ',
      100,
      fontSize: 11.0,
      bold: true,
      align: ui.TextAlign.right,
    );

    // ── Load Font for fallback text ─────────────────────────────────────────
    pw.Font? kannadaFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSansKannada-Regular.ttf');
      kannadaFont = pw.Font.ttf(fontData);
    } catch (_) {}

    // ── Build Landscape PDF Document ─────────────────────────────────────────
    final pdf = pw.Document(
      theme: kannadaFont != null
          ? pw.ThemeData.withFont(base: kannadaFont, bold: kannadaFont)
          : null,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape, // LANDSCAPE MODE
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ── Line 1 Header ──────────────────────────────────────────────
            if (headerLine1Bytes != null)
              pw.Image(pw.MemoryImage(headerLine1Bytes), width: 785),
            pw.SizedBox(height: 6),

            // ── Line 2 Header ──────────────────────────────────────────────
            if (headerLine2Bytes != null)
              pw.Image(pw.MemoryImage(headerLine2Bytes), width: 785),
            pw.SizedBox(height: 10),

            // ── Table ───────────────────────────────────────────────────────
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 1.0),
              columnWidths: const {
                0: pw.FixedColumnWidth(_colDay),
                1: pw.FixedColumnWidth(_colCamp),
                2: pw.FixedColumnWidth(_colDep),
                3: pw.FixedColumnWidth(_colPlace),
                4: pw.FixedColumnWidth(_colRet),
                5: pw.FixedColumnWidth(_colMode),
                6: pw.FixedColumnWidth(_colWork),
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F0F0')),
                  children: [
                    _imgCell(hDayBytes, _colDay - _cellPad * 2),
                    _imgCell(hCampBytes, _colCamp - _cellPad * 2),
                    _imgCell(hDepBytes, _colDep - _cellPad * 2),
                    _imgCell(hPlaceBytes, _colPlace - _cellPad * 2),
                    _imgCell(hRetBytes, _colRet - _cellPad * 2),
                    _imgCell(hModeBytes, _colMode - _cellPad * 2),
                    _imgCell(hWorkBytes, _colWork - _cellPad * 2),
                  ],
                ),
                // 7 Data Rows
                for (int i = 0; i < 7; i++)
                  pw.TableRow(children: [
                    _imgCell(pre[i].dayBytes,   _colDay   - _cellPad * 2),
                    _imgCell(pre[i].campBytes,  _colCamp  - _cellPad * 2),
                    _imgCell(pre[i].depBytes,   _colDep   - _cellPad * 2),
                    _imgCell(pre[i].placeBytes, _colPlace - _cellPad * 2),
                    _imgCell(pre[i].retBytes,   _colRet   - _cellPad * 2),
                    _imgCell(pre[i].modeBytes,  _colMode  - _cellPad * 2),
                    _imgCell(pre[i].workBytes,  _colWork  - _cellPad * 2),
                  ]),
              ],
            ),
            pw.SizedBox(height: 14),

            // ── Footer Submission & Signature ────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (footerBytes != null)
                  pw.Image(pw.MemoryImage(footerBytes), width: 550),
                if (signBytes != null)
                  pw.Image(pw.MemoryImage(signBytes), width: 100),
              ],
            ),
            pw.SizedBox(height: 28),

            // ── Signature Line ───────────────────────────────────────────────
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

    // ── Save & Share PDF ──────────────────────────────────────────────────────
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

  // ── Render Kannada/English text → PNG bytes with dart:ui ─────────────────
  static Future<Uint8List?> _renderText(
    String text,
    double widthPt, {
    double fontSize = _fontSize,
    bool bold = false,
    ui.TextAlign align = ui.TextAlign.left,
  }) async {
    if (text.trim().isEmpty) return null;
    final pxW        = (widthPt * _dpr).round();
    final pxFontSize = fontSize * _dpr;
    final pxPad      = 3.0 * _dpr;

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        textDirection: ui.TextDirection.ltr,
        fontSize: pxFontSize,
        height: 1.35,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xFF000000),
        fontFamily: 'NotoSansKannada',
        fontSize: pxFontSize,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
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

  // ── Helper Image Cell ─────────────────────────────────────────────────────
  static pw.Widget _imgCell(Uint8List? bytes, double widthPt) {
    if (bytes == null) {
      return pw.Padding(
        padding: pw.EdgeInsets.all(_cellPad),
        child: pw.SizedBox(height: 24),
      );
    }
    return pw.Padding(
      padding: pw.EdgeInsets.all(_cellPad),
      child: pw.Image(pw.MemoryImage(bytes), width: widthPt),
    );
  }

  // ── ISO Week Calculation ──────────────────────────────────────────────────
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
    final df   = DateFormat('yyyy-MM-dd');
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
  final Uint8List? dayBytes;
  final Uint8List? campBytes;
  final Uint8List? depBytes;
  final Uint8List? placeBytes;
  final Uint8List? retBytes;
  final Uint8List? modeBytes;
  final Uint8List? workBytes;

  const _PreRendered({
    this.dayBytes,
    this.campBytes,
    this.depBytes,
    this.placeBytes,
    this.retBytes,
    this.modeBytes,
    this.workBytes,
  });
}
