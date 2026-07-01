import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../map_controller.dart';
import '../../../shared/theme.dart';
import '../../../core/utils/geo_calculator.dart';
import '../../../core/utils/kml_engine.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../../../core/utils/pdf_generator.dart';

class ShapeDetailSheet extends StatelessWidget {
  final DrawnShape shape;
  final MapController controller;
  final Future<Uint8List?> Function()? takeScreenshot;

  const ShapeDetailSheet({
    super.key,
    required this.shape,
    required this.controller,
    this.takeScreenshot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: shape.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: shape.color),
                  ),
                  child: Icon(
                    _shapeIcon(shape.type),
                    color: shape.color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shape.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _typeLabel(shape.type),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () {
                    controller.clearSelection();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Stats
          if (shape.type == DrawMode.polygon)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatCard(
                    label: 'Area',
                    value: '${shape.areaHectares.toStringAsFixed(4)} ha',
                    subValue: '${GeoCalculator.hectaresToAcres(shape.areaHectares).toStringAsFixed(4)} ac',
                    icon: Icons.crop_square,
                    color: AppTheme.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  _StatCard(
                    label: 'Perimeter',
                    value: '${shape.perimeterMeters.toStringAsFixed(1)} m',
                    subValue: '${(shape.perimeterMeters / 1000).toStringAsFixed(3)} km',
                    icon: Icons.straighten,
                    color: AppTheme.infoColor,
                  ),
                ],
              ),
            ),

          if (shape.type == DrawMode.path)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatCard(
                label: 'Length',
                value: '${shape.perimeterMeters.toStringAsFixed(1)} m',
                subValue: '${(shape.perimeterMeters / 1000).toStringAsFixed(3)} km',
                icon: Icons.straighten,
                color: AppTheme.infoColor,
              ),
            ),

          if (shape.type == DrawMode.marker)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CoordCard(point: shape.points.first),
            ),

          const SizedBox(height: 12),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionChip(
                  icon: Icons.edit,
                  label: 'Rename',
                  onTap: () => _showRenameDialog(context),
                ),
                _ActionChip(
                  icon: Icons.palette,
                  label: 'Color',
                  onTap: () => _showColorPicker(context),
                ),
                _ActionChip(
                  icon: Icons.save_alt,
                  label: 'Save',
                  onTap: () => _saveShape(context),
                ),
                _ActionChip(
                  icon: Icons.share,
                  label: 'Export KML',
                  onTap: () => _exportKml(context),
                ),
                if (shape.type == DrawMode.polygon)
                  _ActionChip(
                    icon: Icons.print,
                    label: 'Print',
                    color: AppTheme.infoColor,
                    onTap: () => _printPdf(context),
                  ),
                _ActionChip(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: AppTheme.errorColor,
                  onTap: () => _deleteShape(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  IconData _shapeIcon(DrawMode type) {
    switch (type) {
      case DrawMode.polygon:
        return Icons.pentagon;
      case DrawMode.path:
        return Icons.polyline;
      case DrawMode.marker:
        return Icons.place;
      default:
        return Icons.shape_line;
    }
  }

  String _typeLabel(DrawMode type) {
    switch (type) {
      case DrawMode.polygon:
        return 'Polygon';
      case DrawMode.path:
        return 'Path / Line';
      case DrawMode.marker:
        return 'Marker / Point';
      default:
        return 'Shape';
    }
  }

  void _showRenameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: shape.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Rename Shape'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Shape name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                controller.renameShape(shape.id, ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    Color pickedColor = shape.color;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Choose Color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: shape.color,
            availableColors: AppTheme.polygonColors,
            onColorChanged: (c) => pickedColor = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              controller.changeShapeColor(shape.id, pickedColor);
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveShape(BuildContext context) async {
    final saved = await controller.saveSelectedPolygon();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved ? '${shape.name} saved to database' : 'Only polygons can be saved'),
        backgroundColor: saved ? AppTheme.greenPrimary : AppTheme.warningColor,
      ));
    }
  }

  Future<void> _exportKml(BuildContext context) async {
    try {
      final pts = shape.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      final kml = shape.type == DrawMode.polygon
          ? KmlEngine.generatePolygonKml(name: shape.name, points: pts)
          : KmlEngine.generatePathKml(name: shape.name, points: pts);

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save KML File',
        fileName: '${shape.name}.kml',
        type: FileType.custom,
        allowedExtensions: ['kml'],
      );

      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsString(kml);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('KML saved to $outputPath'),
              backgroundColor: AppTheme.greenPrimary,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    if (shape.type != DrawMode.polygon) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF...')),
      );


      final pts = shape.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();

      final path = await PdfGenerator.generatePolygonPdf(
        parts: [
          PolygonPart(
            name: shape.name,
            points: pts,
            areaHectares: shape.areaHectares,
            perimeterMeters: shape.perimeterMeters,
          ),
        ],
        reportTitle: shape.name,
      );

      final pdfBytes = await File(path).readAsBytes();
      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }

  void _deleteShape(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Shape?'),
        content: Text('Delete "${shape.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () {
              controller.deleteShape(shape.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String subValue;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.subValue,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            Text(subValue,
                style:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _CoordCard extends StatelessWidget {
  final dynamic point;
  const _CoordCard({required this.point});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Location',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            'Lat: ${point.latitude.toStringAsFixed(6)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          ),
          Text(
            'Lng: ${point.longitude.toStringAsFixed(6)}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.greenAccent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
