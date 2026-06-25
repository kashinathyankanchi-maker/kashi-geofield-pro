import 'dart:io';
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

  /// Generate a PDF for a polygon and return the file path
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
    final pdfPageFormat = _getPageFormat(pageSize, orientation);
    final now = DateTime.now();
    final dateStr =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(orgName, dateStr, context),
              pw.SizedBox(height: 16),

              // Title
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green800,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  customTitle ?? polygonName,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 12),

              // Map image
              if (mapScreenshot != null) ...[
                pw.ClipRRect(
                  horizontalRadius: 6,
                  verticalRadius: 6,
                  child: pw.Image(
                    pw.MemoryImage(mapScreenshot),
                    width: pdfPageFormat.availableWidth,
                    height: pdfPageFormat.availableHeight * 0.40,
                    fit: pw.BoxFit.cover,
                  ),
                ),
                pw.SizedBox(height: 12),
              ],

              // Details table
              _buildDetailsTable(
                polygonName: polygonName,
                areaHectares: areaHectares,
                perimeterMeters: perimeterMeters,
                points: points,
                dateStr: dateStr,
              ),
              pw.SizedBox(height: 12),

              // Notes
              if (notes != null && notes.isNotEmpty) ...[
                pw.Text('Notes:',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 4),
                pw.Text(notes,
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                pw.SizedBox(height: 12),
              ],

              // Coordinates section
              _buildCoordinatesSection(points),

              pw.Spacer(),
              _buildFooter(context),
            ],
          );
        },
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
    final pdfPageFormat = _getPageFormat(pageSize, orientation);
    final now = DateTime.now();
    final dateStr =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: pdfPageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(orgName, dateStr, context),
              pw.SizedBox(height: 16),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green800,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Village Boundary Map',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      villageName,
                      style: pw.TextStyle(
                        color: PdfColors.greenAccent100,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              if (mapScreenshot != null) ...[
                pw.ClipRRect(
                  horizontalRadius: 6,
                  verticalRadius: 6,
                  child: pw.Image(
                    pw.MemoryImage(mapScreenshot),
                    width: pdfPageFormat.availableWidth,
                    height: pdfPageFormat.availableHeight * 0.40,
                    fit: pw.BoxFit.cover,
                  ),
                ),
                pw.SizedBox(height: 12),
              ],
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  _tableRow('Village Name', villageName),
                  _tableRow('District', district.isEmpty ? 'N/A' : district),
                  _tableRow('State', state.isEmpty ? 'N/A' : state),
                  _tableRow('Area', GeoCalculator.formatArea(areaHectares)),
                  _tableRow(
                    'Perimeter',
                    GeoCalculator.formatPerimeter(GeoCalculator.calculatePerimeterMeters(points)),
                  ),
                  _tableRow('Boundary Points', '${points.length}'),
                  _tableRow('Date', dateStr),
                ],
              ),
              pw.Spacer(),
              _buildFooter(context),
            ],
          );
        },
      ),
    );

    final path = await _savePdf(pdf, villageName);
    await _savePrintHistory(villageName, 'Village', path);
    return path;
  }

  // ─────────────────── HELPERS ───────────────────────────────────────────────

  static pw.Widget _buildHeader(
      String orgName, String dateStr, pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey900,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                orgName,
                style: pw.TextStyle(
                  color: PdfColors.green400,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'GeoField Pro — Professional Field Mapping',
                style: const pw.TextStyle(color: PdfColors.grey400, fontSize: 10),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Generated: $dateStr',
                style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 9),
              ),
            ],
          ),
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
        _tableRow('Area (Hectares)', '${areaHectares.toStringAsFixed(4)} ha'),
        _tableRow('Area (Acres)', '${areaAcres.toStringAsFixed(4)} ac'),
        _tableRow('Area (Sq. Meters)', '${areaSqM.toStringAsFixed(2)} m²'),
        _tableRow('Perimeter', GeoCalculator.formatPerimeter(perimeterMeters)),
        _tableRow('Vertices', '${points.length}'),
        _tableRow('Date Created', dateStr),
      ],
    );
  }

  static pw.Widget _buildCoordinatesSection(List<Map<String, double>> points) {
    final coordStr = points
        .take(20)
        .map((p) =>
            '${p['lat']!.toStringAsFixed(6)}, ${p['lng']!.toStringAsFixed(6)}')
        .join('\n');
    final suffix = points.length > 20 ? '\n... (${points.length - 20} more)' : '';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Coordinates:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            coordStr + suffix,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
          ),
        ),
      ],
    );
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
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900)),
      ),
    ]);
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by kashi GeoField Pro',
              style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 8)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 8)),
        ],
      ),
    );
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

  /// Share PDF file using share_plus
  static Future<void> sharePdf(String pdfPath, String subject) async {
    await Share.shareXFiles(
      [XFile(pdfPath, mimeType: 'application/pdf')],
      subject: subject,
    );
  }
}
