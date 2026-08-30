import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../map_controller.dart';
import '../../../shared/theme.dart';
import '../../../core/utils/geo_calculator.dart';
import '../../../core/utils/kml_engine.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../../../core/utils/pdf_generator.dart';

class ShapeDetailSheet extends StatefulWidget {
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
  State<ShapeDetailSheet> createState() => _ShapeDetailSheetState();
}

class _ShapeDetailSheetState extends State<ShapeDetailSheet> {
  DrawnShape get shape => widget.shape;
  MapController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        mainAxisSize: shape.type == DrawMode.marker ? MainAxisSize.max : MainAxisSize.min,
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

          // ── Marker metadata panel ───────────────────────────────────
          if (shape.type == DrawMode.marker)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badge
                    if (shape.category != null) ...[  
                      _MetaBadge(
                        emoji: _categoryEmoji(shape.category!),
                        label: shape.category!,
                        color: _categoryColor(shape.category!),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Photo
                    if (shape.photoPath != null && File(shape.photoPath!).existsSync()) ...[  
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(shape.photoPath!),
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Description
                    if (shape.description != null && shape.description!.isNotEmpty) ...[  
                      _MetaInfoTile(
                        emoji: '📝',
                        label: 'Description',
                        value: shape.description!,
                      ),
                      const SizedBox(height: 8),
                    ],

                    // GPS Accuracy
                    if (shape.gpsAccuracy != null && shape.gpsAccuracy!.isNotEmpty)
                      _MetaInfoTile(
                        emoji: '📐',
                        label: 'GPS Accuracy',
                        value: shape.gpsAccuracy!,
                        valueColor: const Color(0xFF43A047),
                      ),

                    // Altitude
                    if (shape.altitude != null && shape.altitude!.isNotEmpty)
                      _MetaInfoTile(
                        emoji: '🧭',
                        label: 'Altitude',
                        value: shape.altitude!,
                        valueColor: const Color(0xFF43A047),
                      ),

                    // Coordinates
                    _MetaInfoTile(
                      emoji: '📍',
                      label: 'Coordinates',
                      value:
                          'Lat: ${shape.points.first.latitude.toStringAsFixed(6)}\n'
                          'Lng: ${shape.points.first.longitude.toStringAsFixed(6)}',
                    ),

                    // Officer name
                    if (shape.officerName != null && shape.officerName!.isNotEmpty) ...[  
                      const SizedBox(height: 4),
                      _MetaInfoTile(
                        emoji: '👤',
                        label: 'Officer / Beat',
                        value: shape.officerName!,
                      ),
                    ],

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            )
          else
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
                if (shape.type == DrawMode.path && shape.points.length > 2)
                  _ActionChip(
                    icon: Icons.auto_awesome_mosaic,
                    label: 'To Polygon',
                    color: AppTheme.greenPrimary,
                    onTap: () async {
                      await controller.convertPathToPolygon(shape.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('\${shape.name} converted to Polygon!'), backgroundColor: AppTheme.greenPrimary)
                        );
                      }
                    },
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
    if (type == DrawMode.marker && shape.category != null) {
      return shape.category!;
    }
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

  String _categoryEmoji(String cat) {
    const map = {
      'Tree': '🌳', 'Wildlife': '🐘', 'Fire': '🔥',
      'Illegal activity': '🚨', 'Water source': '💧',
      'Road/track': '🛤️', 'Camp': '⛺', 'Danger': '⚠️', 'Other': '📍',
    };
    return map[cat] ?? '📍';
  }

  Color _categoryColor(String cat) {
    const map = {
      'Tree': Color(0xFF43A047), 'Wildlife': Color(0xFF795548),
      'Fire': Color(0xFFE53935), 'Illegal activity': Color(0xFFD81B60),
      'Water source': Color(0xFF1E88E5), 'Road/track': Color(0xFF757575),
      'Camp': Color(0xFFFF8F00), 'Danger': Color(0xFFFDD835),
    };
    return map[cat] ?? const Color(0xFF2EA043);
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

// ── Marker metadata widgets ───────────────────────────────────────────────────

class _MetaBadge extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  const _MetaBadge({required this.emoji, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaInfoTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color? valueColor;
  const _MetaInfoTile({
    required this.emoji,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
