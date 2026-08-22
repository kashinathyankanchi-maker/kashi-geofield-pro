import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'storage_helper.dart';
import 'geo_calculator.dart';
import '../database/db_helper.dart';
import '../models/print_history_model.dart';

/// Represents one polygon part for multi-part printing
class PolygonPart {
  final String name;
  final List<Map<String, double>> points;
  final double areaHectares;
  final double perimeterMeters;

  const PolygonPart({
    required this.name,
    required this.points,
    required this.areaHectares,
    required this.perimeterMeters,
  });
}

class PdfGenerator {
  // ── Public API ──────────────────────────────────────────────────────────────

  /// Generate a PDF for a single polygon (or multiple parts on one page).
  ///
  /// [parts]         – List of polygon parts (Part 1, Part 2…). If a single
  ///                   polygon, pass a list with one item.
  /// [reportTitle]   – Editable page heading (replaces polygon name in banner).
  /// [orgName]       – Organization name shown in header. Pass '' to hide.
  /// [customDate]    – Override the printed date/time string. If null, uses now.
  static Future<String> generatePolygonPdf({
    required List<PolygonPart> parts,
    String reportTitle = '',
    String orgName = '',
    String? customDate,
    String pageSize = 'A4',
    String orientation = 'portrait',
  }) async {
    assert(parts.isNotEmpty, 'At least one PolygonPart required');
    final pdf = pw.Document();
    final fmt = _getPageFormat(pageSize, orientation);
    final dateStr = customDate ?? _fmtNow();

    // ── Totals ─────────────────────────────────────────────────────────────
    final totalArea = parts.fold(0.0, (s, p) => s + p.areaHectares);
    final totalPerimeter =
        parts.fold(0.0, (s, p) => s + p.perimeterMeters);
    final totalPoints = parts.fold(0, (s, p) => s + p.points.length);
    final displayTitle =
        reportTitle.isNotEmpty ? reportTitle : parts.first.name;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: fmt,
        margin: const pw.EdgeInsets.fromLTRB(30, 24, 30, 24),
        header: (ctx) =>
            _buildHeader(orgName, dateStr, ctx),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 6),

          // ── Title banner (editable) ───────────────────────────────────────
          _titleBanner(displayTitle),
          pw.SizedBox(height: 12),

          // ── Summary stats ─────────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Stats table (left column)
              pw.Expanded(
                flex: 3,
                child: _buildSummaryTable(
                  parts: parts,
                  totalArea: totalArea,
                  totalPerimeter: totalPerimeter,
                  totalPoints: totalPoints,
                  dateStr: dateStr,
                  singlePart: parts.length == 1,
                ),
              ),
              pw.SizedBox(width: 14),
              // Polygon diagram(s) — right column, NO fill, bold border
              pw.Expanded(
                flex: 4,
                child: parts.length == 1
                    ? _buildSingleDiagram(parts.first, fmt)
                    : _buildMultiDiagram(parts, fmt),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── Per-part coordinate tables ────────────────────────────────────
          for (int pi = 0; pi < parts.length; pi++) ...[
            if (parts.length > 1)
              _partHeader('Part ${pi + 1} — ${parts[pi].name}',
                  parts[pi].points.length),
            _buildCoordinatesTable(parts[pi].points, partIndex: pi),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );

    final path = await _savePdf(pdf, displayTitle);
    await _savePrintHistory(displayTitle, 'Polygon', path);
    return path;
  }

  /// Generate PDF for a village boundary
  static Future<String> generateVillagePdf({
    required String villageName,
    required String district,
    required String state,
    required List<Map<String, double>> points,
    required double areaHectares,
    Uint8List? mapScreenshot,
    String reportTitle = '',
    String orgName = '',
    String? customDate,
    String pageSize = 'A4',
    String orientation = 'portrait',
  }) async {
    final pdf = pw.Document();
    final fmt = _getPageFormat(pageSize, orientation);
    final dateStr = customDate ?? _fmtNow();
    final displayTitle = reportTitle.isNotEmpty ? reportTitle : villageName;

    final part = PolygonPart(
      name: villageName,
      points: points,
      areaHectares: areaHectares,
      perimeterMeters: GeoCalculator.calculatePerimeterMeters(points),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: fmt,
        margin: const pw.EdgeInsets.fromLTRB(30, 24, 30, 24),
        header: (ctx) => _buildHeader(orgName, dateStr, ctx),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 6),
          _titleBanner(displayTitle),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Table(
                  border: pw.TableBorder.all(
                      color: PdfColors.grey300, width: 0.5),
                  children: [
                    _tableRow('Village Name', villageName),
                    _tableRow(
                        'District', district.isEmpty ? 'N/A' : district),
                    _tableRow('State', state.isEmpty ? 'N/A' : state),
                    _tableRow(
                        'Area', GeoCalculator.formatArea(areaHectares)),
                    _tableRow(
                      'Perimeter',
                      GeoCalculator.formatPerimeter(
                          GeoCalculator.calculatePerimeterMeters(points)),
                    ),
                    _tableRow('Boundary Points', '${points.length}'),
                    _tableRow('Date', dateStr),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                  flex: 4,
                  child: _buildSingleDiagram(part, fmt)),
            ],
          ),
          pw.SizedBox(height: 14),
          _buildCoordinatesTable(points),
        ],
      ),
    );

    final path = await _savePdf(pdf, villageName);
    await _savePrintHistory(villageName, 'Village', path);
    return path;
  }

  // ─────────────────── BUILDERS ──────────────────────────────────────────────

  static pw.Widget _titleBanner(String title) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: const pw.BoxDecoration(
          color: PdfColors.green800,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.Widget _partHeader(String title, int ptCount) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        decoration: const pw.BoxDecoration(
          color: PdfColors.grey800,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11)),
            pw.Text('$ptCount points',
                style: const pw.TextStyle(
                    color: PdfColors.grey400, fontSize: 9)),
          ],
        ),
      );

  static pw.Widget _buildSummaryTable({
    required List<PolygonPart> parts,
    required double totalArea,
    required double totalPerimeter,
    required int totalPoints,
    required String dateStr,
    required bool singlePart,
  }) {
    final rows = <pw.TableRow>[];

    if (singlePart) {
      final p = parts.first;
      rows.addAll([
        _tableRow('Polygon Name', p.name),
        _tableRow('Area (Hectares)',
            '${p.areaHectares.toStringAsFixed(4)} ha'),
        _tableRow('Area (Acres)',
            '${GeoCalculator.hectaresToAcres(p.areaHectares).toStringAsFixed(4)} ac'),
        _tableRow('Area (Sq. Meters)',
            '${(p.areaHectares * 10000).toStringAsFixed(2)} m²'),
        _tableRow('Perimeter',
            GeoCalculator.formatPerimeter(p.perimeterMeters)),
        _tableRow('Total Waypoints', '${p.points.length}'),
        _tableRow('Date Created', dateStr),
      ]);
    } else {
      // Multi-part summary
      rows.addAll([
        _tableRow('Total Parts', '${parts.length}'),
        _tableRow('Total Area (Hectares)',
            '${totalArea.toStringAsFixed(4)} ha'),
        _tableRow('Total Area (Acres)',
            '${GeoCalculator.hectaresToAcres(totalArea).toStringAsFixed(4)} ac'),
        _tableRow('Total Area (Sq. Meters)',
            '${(totalArea * 10000).toStringAsFixed(2)} m²'),
        _tableRow('Total Perimeter',
            GeoCalculator.formatPerimeter(totalPerimeter)),
        _tableRow('Total Waypoints', '$totalPoints'),
        _tableRow('Date Created', dateStr),
      ]);
      // Per-part mini rows
      for (int i = 0; i < parts.length; i++) {
        final p = parts[i];
        rows.add(_tableRowTinted(
          'Part ${i + 1}',
          '${p.areaHectares.toStringAsFixed(2)} ha  ·  ${p.points.length} pts',
          tint: i % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
        ));
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: rows,
    );
  }

  /// Polygon diagram for a single part — NO fill, bold black border.
  /// Looks like screenshot 2 (physical print style).
  static pw.Widget _buildSingleDiagram(PolygonPart part, PdfPageFormat fmt) {
    const boxW = 185.0;
    const boxH = 165.0;
    return _polygonDiagramCanvas(
      allParts: [part],
      boxW: boxW,
      boxH: boxH,
      showPartLabels: false,
    );
  }

  /// Combined diagram with all parts on one canvas.
  static pw.Widget _buildMultiDiagram(
      List<PolygonPart> parts, PdfPageFormat fmt) {
    const boxW = 185.0;
    const boxH = 165.0;
    return _polygonDiagramCanvas(
      allParts: parts,
      boxW: boxW,
      boxH: boxH,
      showPartLabels: true,
    );
  }

  /// Core polygon canvas — draws all parts on white background, NO fill.
  static pw.Widget _polygonDiagramCanvas({
    required List<PolygonPart> allParts,
    required double boxW,
    required double boxH,
    required bool showPartLabels,
  }) {
    const pad = 24.0;

    // Global bounding box across all parts
    final allPts = allParts.expand((p) => p.points).toList();
    if (allPts.isEmpty) return pw.SizedBox(width: boxW, height: boxH);

    final lats = allPts.map((p) => p['lat']!).toList();
    final lngs = allPts.map((p) => p['lng']!).toList();
    final minLat = lats.reduce(min);
    final maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min);
    final maxLng = lngs.reduce(max);

    final latRange = max((maxLat - minLat).abs(), 0.000001);
    final lngRange = max((maxLng - minLng).abs(), 0.000001);
    final scaleX = (boxW - pad * 2) / lngRange;
    final scaleY = (boxH - pad * 2) / latRange;
    final scale = min(scaleX, scaleY);

    PdfPoint toCanvas(Map<String, double> p) => PdfPoint(
          pad + (p['lng']! - minLng) * scale,
          pad + (maxLat - p['lat']!) * scale,
        );

    // Part colors for multi-part mode
    final partColors = [
      PdfColors.black,
      PdfColors.blue900,
      PdfColors.red900,
      PdfColors.orange900,
      PdfColors.purple900,
    ];

    return pw.Container(
      width: boxW,
      height: boxH,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.CustomPaint(
        size: PdfPoint(boxW, boxH),
        painter: (canvas, size) {
          // Subtle grid
          canvas.setStrokeColor(PdfColors.grey200);
          canvas.setLineWidth(0.25);
          for (int i = 1; i < 5; i++) {
            canvas.drawLine(boxW * i / 5, 0, boxW * i / 5, boxH);
            canvas.drawLine(0, boxH * i / 5, boxW, boxH * i / 5);
          }
          canvas.strokePath();

          // Draw each part
          for (int pi = 0; pi < allParts.length; pi++) {
            final part = allParts[pi];
            if (part.points.length < 2) continue;
            final pts = part.points.map(toCanvas).toList();
            final lineColor = allParts.length > 1
                ? partColors[pi % partColors.length]
                : PdfColors.black;

            // Polygon outline — bold, NO fill (white interior = clean)
            canvas.setStrokeColor(lineColor);
            canvas.setLineWidth(2.0);
            canvas.moveTo(pts[0].x, pts[0].y);
            for (int i = 1; i < pts.length; i++) {
              canvas.lineTo(pts[i].x, pts[i].y);
            }
            canvas.closePath();
            canvas.strokePath(); // stroke only — NO fill

            // Vertex labels — square box style (matching physical print)
            for (int i = 0; i < pts.length; i++) {
              final p = pts[i];
              const bw = 14.0;
              const bh = 9.0;

              // Small white box with black border
              canvas.setFillColor(PdfColors.white);
              canvas.setStrokeColor(lineColor);
              canvas.setLineWidth(0.8);
              canvas.drawRect(p.x - bw / 2, p.y - bh / 2, bw, bh);
              canvas.fillAndStrokePath();

              // Dot at vertex
              canvas.setFillColor(lineColor);
              canvas.drawEllipse(p.x, p.y + bh / 2 + 2.5, 1.5, 1.5);
              canvas.fillPath();
            }

            // Part label in corner — set color for potential future use
            if (showPartLabels && pts.isNotEmpty) {
              canvas.setFillColor(lineColor);
            }
          }
        },
      ),
    );
  }

  /// Full numbered coordinate table — ALL points, no truncation.
  static pw.Widget _buildCoordinatesTable(List<Map<String, double>> points,
      {int partIndex = 0}) {
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.green800),
      children: [
        _ch('#'),
        _ch('WPT'),
        _ch('Latitude (N)'),
        _ch('Longitude (E)'),
        _ch('DMS Latitude'),
        _ch('DMS Longitude'),
      ],
    );

    final dataRows = <pw.TableRow>[];
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final wpt = (i + 1).toString().padLeft(3, '0');
      final isEven = i % 2 == 0;
      final lat = p['lat']!;
      final lng = p['lng']!;

      dataRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
          color: isEven ? PdfColors.grey50 : PdfColors.white,
        ),
        children: [
          _cd('${i + 1}'),
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: const pw.BoxDecoration(
                color: PdfColors.yellow,
                borderRadius:
                    pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Text(wpt,
                  style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black)),
            ),
          ),
          _cd(lat.toStringAsFixed(6)),
          _cd(lng.toStringAsFixed(6)),
          _cd(_dms(lat, isLat: true), size: 7.5),
          _cd(_dms(lng, isLat: false), size: 7.5),
        ],
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 3,
              height: 13,
              margin: const pw.EdgeInsets.only(right: 6),
              decoration: const pw.BoxDecoration(
                color: PdfColors.green700,
                borderRadius:
                    pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.Text(
              'Waypoint Coordinate List  (${points.length} points)',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Table(
          border:
              pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
          columnWidths: const {
            0: pw.FixedColumnWidth(18),
            1: pw.FixedColumnWidth(30),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.6),
            5: pw.FlexColumnWidth(1.6),
          },
          children: [headerRow, ...dataRows],
        ),
      ],
    );
  }

  // ─────────────────── PRIVATE HELPERS ───────────────────────────────────────

  static pw.Widget _buildHeader(
      String orgName, String dateStr, pw.Context ctx) {
    // If orgName is empty, show minimal header
    final showOrg = orgName.trim().isNotEmpty;
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 8, 14, 8),
      margin: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey900,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (showOrg)
                pw.Text(orgName,
                    style: pw.TextStyle(
                        color: PdfColors.green400,
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold))
              else
                pw.SizedBox(height: 0),
              pw.Text('GeoField Pro — Professional Field Mapping',
                  style: const pw.TextStyle(
                      color: PdfColors.grey400, fontSize: 9)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Generated: $dateStr',
                  style: const pw.TextStyle(
                      color: PdfColors.grey400, fontSize: 9)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                      color: PdfColors.grey500, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('GeoField Pro — Field Mapping Report',
                style: const pw.TextStyle(
                    color: PdfColors.grey500, fontSize: 8)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    color: PdfColors.grey500, fontSize: 8)),
          ],
        ),
      );

  static pw.Widget _ch(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(t,
            style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8)),
      );

  static pw.Widget _cd(String t, {double size = 8}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Text(t,
            style:
                pw.TextStyle(fontSize: size, color: PdfColors.grey900)),
      );

  static pw.TableRow _tableRow(String label, String value) =>
      pw.TableRow(children: [
        pw.Padding(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: PdfColors.grey800)),
        ),
        pw.Padding(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(value,
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey900)),
        ),
      ]);

  static pw.TableRow _tableRowTinted(
          String label, String value, {required PdfColor tint}) =>
      pw.TableRow(
        decoration: pw.BoxDecoration(color: tint),
        children: [
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9.5,
                    color: PdfColors.grey700)),
          ),
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: pw.Text(value,
                style: const pw.TextStyle(
                    fontSize: 9.5, color: PdfColors.grey900)),
          ),
        ],
      );

  static String _dms(double decimal, {required bool isLat}) {
    final dir = isLat
        ? (decimal >= 0 ? 'N' : 'S')
        : (decimal >= 0 ? 'E' : 'W');
    final abs = decimal.abs();
    final deg = abs.floor();
    final minFull = (abs - deg) * 60;
    final min = minFull.floor();
    final sec = (minFull - min) * 60;
    return "$dir $deg° ${min}' ${sec.toStringAsFixed(1)}\"";
  }

  static String _fmtNow() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}  '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  static PdfPageFormat _getPageFormat(String pageSize, String orientation) {
    PdfPageFormat fmt;
    switch (pageSize.toUpperCase()) {
      case 'A3':
        fmt = PdfPageFormat.a3;
        break;
      case 'LETTER':
        fmt = PdfPageFormat.letter;
        break;
      default:
        fmt = PdfPageFormat.a4;
    }
    return orientation.toLowerCase() == 'landscape' ? fmt.landscape : fmt;
  }

  static Future<String> _savePdf(pw.Document pdf, String name) async {
    final dir = Directory(await StorageHelper.getAppStorageDirectory());
    final safe = name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/pdf_${safe}_$ts.pdf';
    await File(path).writeAsBytes(await pdf.save());
    return path;
  }

  static Future<void> _savePrintHistory(
      String name, String type, String path) async {
    await DbHelper().insertPrintHistory(PrintHistoryModel(
      mapType: type,
      mapName: name,
      pdfPath: path,
      printedAt: DateTime.now().toIso8601String(),
    ));
  }

  static Future<void> sharePdf(String pdfPath, String subject) async {
    await Share.shareXFiles(
      [XFile(pdfPath, mimeType: 'application/pdf')],
      subject: subject,
    );
  }
}
