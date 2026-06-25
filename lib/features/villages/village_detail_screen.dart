import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import '../../shared/theme.dart';
import '../../core/models/village_model.dart';
import '../../core/utils/kml_engine.dart';
import '../../core/utils/geo_calculator.dart';
import '../../core/utils/pdf_generator.dart';

class VillageDetailScreen extends StatefulWidget {
  final VillageModel village;
  const VillageDetailScreen({super.key, required this.village});

  @override
  State<VillageDetailScreen> createState() => _VillageDetailScreenState();
}

class _VillageDetailScreenState extends State<VillageDetailScreen> {
  bool _isExportingKml = false;
  bool _isGeneratingPdf = false;

  List<Map<String, double>> get _coordinates {
    try {
      final list = jsonDecode(widget.village.coordinates) as List;
      return list
          .map((e) => {
                'lat': (e['lat'] as num).toDouble(),
                'lng': (e['lng'] as num).toDouble(),
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _exportKml() async {
    setState(() => _isExportingKml = true);
    try {
      final pts = _coordinates;
      final kml = KmlEngine.generatePolygonKml(
        name: widget.village.villageName,
        points: pts,
        description:
            'District: ${widget.village.district}, State: ${widget.village.state}',
      );
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/${widget.village.villageName.replaceAll(RegExp(r'[^\w]'), '_')}.kml');
      await file.writeAsString(kml);
      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/vnd.google-earth.kml+xml')],
          subject: 'KML - ${widget.village.villageName}',
        );
      }
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExportingKml = false);
    }
  }

  Future<void> _generateAndSharePdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final pts = _coordinates;
      final path = await PdfGenerator.generateVillagePdf(
        villageName: widget.village.villageName,
        district: widget.village.district,
        state: widget.village.state,
        points: pts,
        areaHectares: widget.village.areaHectares,
      );
      if (mounted) {
        await PdfGenerator.sharePdf(path, 'Village Report - ${widget.village.villageName}');
      }
    } catch (e) {
      _showSnack('PDF generation failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _printPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final pts = _coordinates;
      final path = await PdfGenerator.generateVillagePdf(
        villageName: widget.village.villageName,
        district: widget.village.district,
        state: widget.village.state,
        points: pts,
        areaHectares: widget.village.areaHectares,
      );
      final pdfBytes = await File(path).readAsBytes();
      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
    } catch (e) {
      _showSnack('Print failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.errorColor : AppTheme.greenPrimary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final village = widget.village;
    final coords = _coordinates;
    final perimeter = GeoCalculator.calculatePerimeterMeters(coords);

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Text(village.villageName),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Share PDF',
            onPressed: _isGeneratingPdf ? null : _generateAndSharePdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Village Info Card ───────────────────────────────────────────
            _SectionCard(
              title: 'Village Information',
              icon: Icons.info_outline,
              children: [
                _InfoRow('Village Name', village.villageName),
                if (village.district.isNotEmpty)
                  _InfoRow('District', village.district),
                if (village.state.isNotEmpty)
                  _InfoRow('State', village.state),
                _InfoRow('Area', GeoCalculator.formatArea(village.areaHectares)),
                _InfoRow(
                  'Area (Acres)',
                  '${GeoCalculator.hectaresToAcres(village.areaHectares).toStringAsFixed(4)} ac',
                ),
                _InfoRow('Perimeter', GeoCalculator.formatPerimeter(perimeter)),
                _InfoRow('Boundary Points', '${coords.length}'),
                if (village.sourceFile.isNotEmpty)
                  _InfoRow('Source File', village.sourceFile),
                _InfoRow('Imported', village.createdAt.substring(0, 10)),
              ],
            ),
            const SizedBox(height: 12),

            // ── Coordinates Preview ─────────────────────────────────────────
            if (coords.isNotEmpty)
              _SectionCard(
                title: 'Boundary Coordinates',
                icon: Icons.location_on_outlined,
                children: [
                  ...coords.take(10).indexed.map((entry) {
                    final i = entry.$1;
                    final c = entry.$2;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppTheme.infoColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                  color: AppTheme.infoColor, fontSize: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${c['lat']!.toStringAsFixed(6)}, ${c['lng']!.toStringAsFixed(6)}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ]),
                    );
                  }),
                  if (coords.length > 10)
                    Text(
                      '… and ${coords.length - 10} more coordinates',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                ],
              ),
            const SizedBox(height: 12),

            // ── Export Actions ──────────────────────────────────────────────
            _SectionCard(
              title: 'Export & Share',
              icon: Icons.share_outlined,
              children: [
                _ActionButton(
                  icon: Icons.map_outlined,
                  label: 'Export as KML',
                  subtitle: 'Share boundary as KML file',
                  isLoading: _isExportingKml,
                  onTap: _exportKml,
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Share PDF Report',
                  subtitle: 'Generate and share PDF with map details',
                  isLoading: _isGeneratingPdf,
                  onTap: _generateAndSharePdf,
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Icons.print_outlined,
                  label: 'Print PDF',
                  subtitle: 'Print to WiFi or Bluetooth printer',
                  isLoading: _isGeneratingPdf,
                  onTap: _printPdf,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: AppTheme.greenAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppTheme.borderColor),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.greenPrimary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: AppTheme.greenAccent),
                      ),
                    )
                  : Icon(icon, color: AppTheme.greenAccent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}
