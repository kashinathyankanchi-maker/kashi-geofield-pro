import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'geo_calculator.dart';
import '../database/db_helper.dart';
import '../models/print_history_model.dart';

class PdfGenerator {
  static const String _orgName = 'kashi GeoField Pro';

  /// Generate a professional PDF for a polygon.
  /// The PDF includes:
  ///  - Page 1: Header, title banner, stats table, polygon diagram (no map bg), full coordinate table
  ///  - Continues on page 2 if coordinate list is long
  static Future<String> generatePolygonPdf({
    required String polygonName,
    required List<Map<String, double>> points,
    required double areaHectares,
    required double perimeterMeters,
    required String color,
    Uint8List? mapScreenshot,
    String? customTitle,
    String? notes,
    String pageSize = 'A4',
    String orientation = 'portrait',
    String orgName = _orgName,
  }) async {
    final pdf = pw.Document();
    final fmt = _getPageFormat(pageSize, orientation);
    final now = DateTime.now();
    final dateStr = _fmtDate(now);
    final title = customTitle ?? polygonName;

    // ── Page 1: header + diagram + stats + coords ────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: fmt,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => _buildHeader(orgName, dateStr, ctx),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 8),

          // ── Title banner ──────────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: const pw.BoxDecoration(
              color: PdfColors.green800,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (title != polygonName)
                  pw.Text(
                    polygonName,
                    style: const pw.TextStyle(
                      color: PdfColors.greenAccent100,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // ── Two-column: stats + polygon diagram ───────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Stats table (left)
              pw.Expanded(
                flex: 3,
                child: _buildDetailsTable(
                  polygonName: polygonName,
                  areaHectares: areaHectares,
                  perimeterMeters: perimeterMeters,
                  points: points,
                  dateStr: dateStr,
                ),
              ),
              pw.SizedBox(width: 12),
              // Polygon diagram (right) — clean white, NO map background
              pw.Expanded(
                flex: 4,
                child: _buildPolygonDiagram(points, fmt),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── Notes ─────────────────────────────────────────────────────────
          if (notes != null && notes.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Notes:',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.SizedBox(height: 4),
                  pw.Text(notes,
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
          ],

          // ── Full waypoint coordinate table (all points, no truncation) ────
          _buildCoordinatesSection(points),
        ],
      ),
    );

    final path = await _savePdf(pdf, polygonName);
    await _savePrintHistory(polygonName, 'Polygon', path);
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
    String pageSize = 'A4',
    String orientation = 'portrait',
    String orgName = _orgName,
  }) async {
    final pdf = pw.Document();
    final fmt = _getPageFormat(pageSize, orientation);
    final now = DateTime.now();
    final dateStr = _fmtDate(now);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: fmt,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => _buildHeader(orgName, dateStr, ctx),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue800,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Village Boundary Map',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(villageName,
                    style: const pw.TextStyle(
                        color: PdfColors.lightBlue100, fontSize: 14)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  children: [
                    _tableRow('Village Name', villageName),
                    _tableRow(
                        'District', district.isEmpty ? 'N/A' : district),
                    _tableRow('State', state.isEmpty ? 'N/A' : state),
                    _tableRow('Area', GeoCalculator.formatArea(areaHectares)),
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
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 4,
                child: _buildPolygonDiagram(points, fmt),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _buildCoordinatesSection(points),
        ],
      ),
    );

    final path = await _savePdf(pdf, villageName);
    await _savePrintHistory(villageName, 'Village', path);
    return path;
  }

  // ─────────────────── HELPERS ─────────────────────────────────────────────

  static String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static pw.Widget _buildHeader(
      String orgName, String dateStr, pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
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
              pw.Text(orgName,
                  style: pw.TextStyle(
                      color: PdfColors.green400,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold)),
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
                      color: PdfColors.grey500, fontSize: 9)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                      color: PdfColors.grey500, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border:
            pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by kashi GeoField Pro',
              style:
                  const pw.TextStyle(color: PdfColors.grey500, fontSize: 8)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style:
                  const pw.TextStyle(color: PdfColors.grey500, fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _buildDetailsTable({
    required String polygonName,
    required double areaHectares,
    required double perimeterMeters,
    required List<Map<String, double>> points,
    required String dateStr,
  }) {
    final areaAcres = GeoCalculator.hectaresToAcres(areaHectares);
    final areaSqM = areaHectares * 10000;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        _tableRow('Polygon Name', polygonName),
        _tableRow(
            'Area (Hectares)', '${areaHectares.toStringAsFixed(4)} ha'),
        _tableRow(
            'Area (Acres)', '${areaAcres.toStringAsFixed(4)} ac'),
        _tableRow(
            'Area (Sq. Meters)', '${areaSqM.toStringAsFixed(2)} m²'),
        _tableRow(
            'Perimeter', GeoCalculator.formatPerimeter(perimeterMeters)),
        _tableRow('Total Waypoints', '${points.length}'),
        _tableRow('Date Created', dateStr),
      ],
    );
  }

  /// Draws a clean polygon diagram on white background — NO map tiles.
  /// Polygon is bold with numbered vertex labels.
  static pw.Widget _buildPolygonDiagram(
      List<Map<String, double>> points, PdfPageFormat fmt) {
    if (points.isEmpty) return pw.SizedBox();

    const boxW = 180.0;
    const boxH = 160.0;
    const padding = 22.0;

    // Compute bounding box
    final lats = points.map((p) => p['lat']!).toList();
    final lngs = points.map((p) => p['lng']!).toList();
    final minLat = lats.reduce(min);
    final maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min);
    final maxLng = lngs.reduce(max);

    final latRange = (maxLat - minLat).abs();
    final lngRange = (maxLng - minLng).abs();
    final scaleX = latRange < 0.000001 ? 1.0 : (boxW - padding * 2) / lngRange;
    final scaleY = lngRange < 0.000001 ? 1.0 : (boxH - padding * 2) / latRange;
    final scale = min(scaleX, scaleY);

    // Normalize points
    List<PdfPoint> pts = points.map((p) {
      final x = padding + (p['lng']! - minLng) * scale;
      final y = padding + (maxLat - p['lat']!) * scale;
      return PdfPoint(x, y);
    }).toList();

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
          if (pts.length < 2) return;

          // Grid lines (subtle)
          canvas.setStrokeColor(PdfColors.grey200);
          canvas.setLineWidth(0.3);
          for (int i = 1; i < 4; i++) {
            canvas.drawLine(
                boxW * i / 4, 0, boxW * i / 4, boxH);
            canvas.drawLine(
                0, boxH * i / 4, boxW, boxH * i / 4);
          }
          canvas.strokePath();

          // Polygon fill
          canvas.setFillColor(const PdfColor(0.18, 0.63, 0.26, 0.15));
          canvas.moveTo(pts[0].x, pts[0].y);
          for (int i = 1; i < pts.length; i++) {
            canvas.lineTo(pts[i].x, pts[i].y);
          }
          canvas.closePath();
          canvas.fillPath();

          // Polygon border — BOLD
          canvas.setStrokeColor(const PdfColor(0.0, 0.5, 0.2));
          canvas.setLineWidth(2.5);
          canvas.moveTo(pts[0].x, pts[0].y);
          for (int i = 1; i < pts.length; i++) {
            canvas.lineTo(pts[i].x, pts[i].y);
          }
          canvas.closePath();
          canvas.strokePath();

          // Vertex dots
          for (int i = 0; i < pts.length; i++) {
            final p = pts[i];

            // Yellow dot with black border
            canvas.setFillColor(PdfColors.yellow);
            canvas.setStrokeColor(PdfColors.black);
            canvas.setLineWidth(0.6);
            canvas.drawEllipse(p.x, p.y, 4, 4);
            canvas.fillAndStrokePath();
          }
        },
      ),
    );
  }

  /// Full coordinate table — ALL waypoints, no truncation.
  /// Uses multi-page support via pw.MultiPage.
  static pw.Widget _buildCoordinatesSection(
      List<Map<String, double>> points) {
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.green800),
      children: [
        _coordHeader('#'),
        _coordHeader('WPT'),
        _coordHeader('Latitude (N)'),
        _coordHeader('Longitude (E)'),
        _coordHeader('DMS Lat'),
        _coordHeader('DMS Lng'),
      ],
    );

    final dataRows = <pw.TableRow>[];
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final wptLabel = (i + 1).toString().padLeft(3, '0');
      final isEven = i % 2 == 0;
      final lat = p['lat']!;
      final lng = p['lng']!;
      dataRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
          color: isEven ? PdfColors.grey50 : PdfColors.white,
        ),
        children: [
          _coordCell('${i + 1}', bold: false),
          _coordCellWidget(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: const pw.BoxDecoration(
                color: PdfColors.yellow,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Text(wptLabel,
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black)),
            ),
          ),
          _coordCell(lat.toStringAsFixed(6)),
          _coordCell(lng.toStringAsFixed(6)),
          _coordCell(_decToDms(lat, isLat: true), size: 7.5),
          _coordCell(_decToDms(lng, isLat: false), size: 7.5),
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
              height: 14,
              margin: const pw.EdgeInsets.only(right: 6),
              decoration: const pw.BoxDecoration(
                  color: PdfColors.green700,
                  borderRadius:
                      pw.BorderRadius.all(pw.Radius.circular(2))),
            ),
            pw.Text(
              'Waypoint Coordinate List  (${points.length} points)',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                  color: PdfColors.grey800),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
          columnWidths: {
            0: const pw.FixedColumnWidth(20),
            1: const pw.FixedColumnWidth(32),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.5),
            5: const pw.FlexColumnWidth(1.5),
          },
          children: [headerRow, ...dataRows],
        ),
      ],
    );
  }

  static pw.Widget _coordHeader(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8)),
      );

  static pw.Widget _coordCell(String text,
      {bool bold = false, double size = 8}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: size,
                color: PdfColors.grey900,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  static pw.Widget _coordCellWidget(pw.Widget child) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: child,
      );

  /// Convert decimal degrees to DMS string
  static String _decToDms(double decimal, {required bool isLat}) {
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

  static pw.TableRow _tableRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(label,
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.grey800)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(value,
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey900)),
      ),
    ]);
  }

  static PdfPageFormat _getPageFormat(String pageSize, String orientation) {
    PdfPageFormat format;
    switch (pageSize.toUpperCase()) {
      case 'A3':
        format = PdfPageFormat.a3;
        break;
      case 'LETTER':
        format = PdfPageFormat.letter;
        break;
      default:
        format = PdfPageFormat.a4;
    }
    if (orientation.toLowerCase() == 'landscape') {
      format = format.landscape;
    }
    return format;
  }

  static Future<String> _savePdf(pw.Document pdf, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeFilename = name.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/pdf_${safeFilename}_$timestamp.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
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

  /// Share a PDF file using share_plus
  static Future<void> sharePdf(String pdfPath, String subject) async {
    await Share.shareXFiles(
      [XFile(pdfPath, mimeType: 'application/pdf')],
      subject: subject,
    );
  }
}
