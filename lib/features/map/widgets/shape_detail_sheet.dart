import 'dart:async';
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
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';

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

class _ShapeDetailSheetState extends State<ShapeDetailSheet>
    with SingleTickerProviderStateMixin {
  DrawnShape get shape => widget.shape;
  MapController get controller => widget.controller;

  // Edit mode (Google-Earth-style editor)
  bool _editMode = false;
  late TabController _tabController;

  // Edit fields
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late Color _outlineColor;
  late Color _fillColor;
  double _outlineWidth = 4.0;
  double _fillOpacity = 0.25;
  bool _moreSettingsExpanded = false;
  String? _mediaPath;

  static const List<double> _widthOptions = [1, 2, 3, 4, 5, 6, 8, 10];
  static const List<double> _opacityOptions = [0, 0.1, 0.25, 0.5, 0.75, 1.0];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _titleCtrl = TextEditingController(text: shape.name);
    _descCtrl = TextEditingController(text: shape.description ?? '');
    _outlineColor = shape.color;
    _fillColor = shape.color;
    _mediaPath = shape.photoPath;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Save all edits ─────────────────────────────────────────────────────────
  void _applyEdits() {
    final newName = _titleCtrl.text.trim().isEmpty ? shape.name : _titleCtrl.text.trim();
    final newDesc = _descCtrl.text.trim();

    // Rename if changed
    if (newName != shape.name) {
      controller.renameShape(shape.id, newName);
    }

    // Update color, description, photo in one call
    controller.updateShapeMeta(
      shape.id,
      description: newDesc,
      photoPath: _mediaPath,
      color: _outlineColor != shape.color ? _outlineColor : null,
    );

    setState(() => _editMode = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editMode && shape.type != DrawMode.marker) {
      return _buildEditSheet();
    }
    return _buildInfoSheet();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EDIT SHEET — Google-Earth style editor
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildEditSheet() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ───────────────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.edit_rounded, color: AppTheme.greenAccent, size: 20),
                const SizedBox(width: 8),
                const Text('Edit', style: TextStyle(
                  color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                // Local KML chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.greenPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.greenPrimary.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.storage_rounded, color: AppTheme.greenAccent, size: 12),
                      SizedBox(width: 4),
                      Text('Local KML', style: TextStyle(
                        color: AppTheme.greenAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.check_box_rounded, color: AppTheme.textSecondary, size: 14),
                  SizedBox(width: 4),
                  Text('Saved on this device',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ]),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _editMode = false),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),
          const Divider(color: AppTheme.borderColor, height: 1),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Title field ─────────────────────────────────────────
                  _EditLabel(label: 'Title'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.bgSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.greenAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Description / Media row ─────────────────────────────
                  Row(children: [
                    _OutlineButton(
                      icon: Icons.add,
                      label: '+ Description',
                      color: AppTheme.infoColor,
                      onTap: () => _showDescriptionEditor(),
                    ),
                    const SizedBox(width: 16),
                    _OutlineButton(
                      icon: Icons.photo_library_rounded,
                      label: '+ Media',
                      color: AppTheme.warningColor,
                      onTap: () => _pickMedia(),
                    ),
                  ]),

                  // Description preview
                  if (_descCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Text(_descCtrl.text,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ),
                  ],

                  // Media preview
                  if (_mediaPath != null && File(_mediaPath!).existsSync()) ...[
                    const SizedBox(height: 8),
                    Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(_mediaPath!),
                          height: 120, width: double.infinity, fit: BoxFit.cover),
                      ),
                      Positioned(top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _mediaPath = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ]),
                  ],

                  const SizedBox(height: 20),
                  const Divider(color: AppTheme.borderColor, height: 1),
                  const SizedBox(height: 14),

                  // ── Outline section ─────────────────────────────────────
                  _SectionRow(
                    label: 'Outline',
                    child: Row(children: [
                      // Width dropdown
                      _FieldGroup(
                        label: 'Width',
                        child: _StyledDropdown<double>(
                          value: _outlineWidth,
                          items: _widthOptions,
                          display: (v) => '${v.toStringAsFixed(0)} px',
                          onChanged: (v) => setState(() => _outlineWidth = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Color picker
                      _FieldGroup(
                        label: 'Color',
                        child: _ColorSwatch(
                          color: _outlineColor,
                          onTap: () => _pickColor(
                            title: 'Outline Color',
                            current: _outlineColor,
                            onPicked: (c) => setState(() => _outlineColor = c),
                          ),
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 14),

                  // ── Fill section ────────────────────────────────────────
                  _SectionRow(
                    label: 'Fill',
                    child: Row(children: [
                      // Opacity dropdown
                      _FieldGroup(
                        label: 'Opacity',
                        child: _StyledDropdown<double>(
                          value: _fillOpacity,
                          items: _opacityOptions,
                          display: (v) => '${(v * 100).toStringAsFixed(0)}%',
                          onChanged: (v) => setState(() => _fillOpacity = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Fill color picker
                      _FieldGroup(
                        label: 'Color',
                        child: _ColorSwatch(
                          color: _fillColor,
                          onTap: () => _pickColor(
                            title: 'Fill Color',
                            current: _fillColor,
                            onPicked: (c) => setState(() => _fillColor = c),
                          ),
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 14),
                  const Divider(color: AppTheme.borderColor, height: 1),
                  const SizedBox(height: 6),

                  // ── More settings ────────────────────────────────────────
                  InkWell(
                    onTap: () => setState(() => _moreSettingsExpanded = !_moreSettingsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        const Text('More settings',
                          style: TextStyle(color: AppTheme.textPrimary,
                            fontSize: 15, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Icon(
                          _moreSettingsExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppTheme.textSecondary,
                        ),
                      ]),
                    ),
                  ),

                  if (_moreSettingsExpanded) ...[
                    const SizedBox(height: 8),
                    _MoreSettingTile(
                      icon: Icons.straighten_rounded,
                      label: 'Points',
                      value: '${shape.points.length} vertices',
                    ),
                    if (shape.type == DrawMode.polygon) ...[
                      _MoreSettingTile(
                        icon: Icons.crop_square_rounded,
                        label: 'Area',
                        value: GeoCalculator.formatArea(shape.areaHectares),
                      ),
                      _MoreSettingTile(
                        icon: Icons.loop_rounded,
                        label: 'Perimeter',
                        value: GeoCalculator.formatPerimeter(shape.perimeterMeters),
                      ),
                    ],
                    if (shape.type == DrawMode.path)
                      _MoreSettingTile(
                        icon: Icons.straighten_rounded,
                        label: 'Length',
                        value: GeoCalculator.formatPerimeter(shape.perimeterMeters),
                      ),
                    const SizedBox(height: 4),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Bottom bar: Done + toolbar ───────────────────────────────────
          const Divider(color: AppTheme.borderColor, height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16,
              MediaQuery.of(context).viewInsets.bottom + 14),
            child: Row(children: [
              // Done button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.greenPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () {
                  _applyEdits();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              // Visibility toggle
              _ToolbarBtn(icon: Icons.visibility_rounded, tooltip: 'Toggle Visibility',
                onTap: () {}),
              const SizedBox(width: 8),
              // Polygon/Path icon
              _ToolbarBtn(
                icon: shape.type == DrawMode.polygon
                    ? Icons.pentagon_rounded : Icons.polyline_rounded,
                tooltip: 'Shape Type',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              // Undo
              _ToolbarBtn(icon: Icons.undo_rounded, tooltip: 'Undo',
                onTap: () {}),
              const SizedBox(width: 8),
              // Redo
              _ToolbarBtn(icon: Icons.redo_rounded, tooltip: 'Redo',
                onTap: () {}),
              const Spacer(),
              // More menu
              _ToolbarBtn(icon: Icons.more_vert_rounded, tooltip: 'More',
                onTap: () => _showMoreMenu(context)),
            ]),
          ),
        ],
      ),
    );
  }

  void _showDescriptionEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16,
          MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Description', style: TextStyle(
              color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: AppTheme.textSecondary),
              onPressed: () => Navigator.pop(ctx),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter description…',
              hintStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.greenAccent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.greenPrimary,
              minimumSize: const Size(double.infinity, 44)),
            onPressed: () {
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Save Description'),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _mediaPath = picked.path);
    }
  }

  void _pickColor({
    required String title,
    required Color current,
    required void Function(Color) onPicked,
  }) {
    Color temp = current;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: current,
            availableColors: AppTheme.polygonColors,
            onColorChanged: (c) => temp = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.greenPrimary),
            onPressed: () { onPicked(temp); Navigator.pop(ctx); },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.share, color: AppTheme.greenAccent),
          title: const Text('Export KML', style: TextStyle(color: AppTheme.textPrimary)),
          onTap: () { Navigator.pop(ctx); _exportKml(context); },
        ),
        if (shape.type == DrawMode.polygon)
          ListTile(
            leading: const Icon(Icons.print, color: AppTheme.infoColor),
            title: const Text('Print PDF', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () { Navigator.pop(ctx); _printPdf(context); },
          ),
        if (shape.type == DrawMode.path && shape.points.length > 2)
          ListTile(
            leading: const Icon(Icons.auto_awesome_mosaic, color: AppTheme.greenPrimary),
            title: const Text('Convert to Polygon', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () async {
              Navigator.pop(ctx);
              await controller.convertPathToPolygon(shape.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
          title: const Text('Delete Shape', style: TextStyle(color: AppTheme.errorColor)),
          onTap: () { Navigator.pop(ctx); _deleteShape(context); },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INFO SHEET — Original view with Edit button
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildInfoSheet() {
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
              width: 40, height: 4,
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
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: shape.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: shape.color),
                  ),
                  child: Icon(_shapeIcon(shape.type), color: shape.color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shape.name, style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(_typeLabel(shape.type),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                // Edit button (shows edit sheet)
                if (shape.type != DrawMode.marker)
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: AppTheme.greenAccent),
                    tooltip: 'Edit Shape',
                    onPressed: () => setState(() => _editMode = true),
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
              child: Row(children: [
                _StatCard(
                  label: 'Area',
                  value: '${shape.areaHectares.toStringAsFixed(4)} ha',
                  subValue: '${GeoCalculator.hectaresToAcres(shape.areaHectares).toStringAsFixed(4)} ac',
                  icon: Icons.crop_square, color: AppTheme.greenAccent,
                ),
                const SizedBox(width: 8),
                _StatCard(
                  label: 'Perimeter',
                  value: '${shape.perimeterMeters.toStringAsFixed(1)} m',
                  subValue: '${(shape.perimeterMeters / 1000).toStringAsFixed(3)} km',
                  icon: Icons.straighten, color: AppTheme.infoColor,
                ),
              ]),
            ),

          if (shape.type == DrawMode.path)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatCard(
                label: 'Length',
                value: '${shape.perimeterMeters.toStringAsFixed(1)} m',
                subValue: '${(shape.perimeterMeters / 1000).toStringAsFixed(3)} km',
                icon: Icons.straighten, color: AppTheme.infoColor,
              ),
            ),

          // ── Marker metadata panel ────────────────────────────────────────
          if (shape.type == DrawMode.marker)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shape.category != null) ...[
                      _MetaBadge(
                        emoji: _categoryEmoji(shape.category!),
                        label: shape.category!,
                        color: _categoryColor(shape.category!),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (shape.photoPath != null && File(shape.photoPath!).existsSync()) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(shape.photoPath!),
                          width: double.infinity, height: 200, fit: BoxFit.cover,
                          cacheWidth: 900, cacheHeight: 600),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (shape.voiceNotePath != null &&
                        shape.voiceNotePath!.isNotEmpty &&
                        shape.voiceNotePath != 'voice_recorded' &&
                        File(shape.voiceNotePath!).existsSync()) ...[
                      _VoiceNotePlayer(path: shape.voiceNotePath!),
                      const SizedBox(height: 8),
                    ],
                    if (shape.description != null && shape.description!.isNotEmpty) ...[
                      _MetaInfoTile(emoji: '📝', label: 'Description', value: shape.description!),
                      const SizedBox(height: 8),
                    ],
                    if (shape.gpsAccuracy != null && shape.gpsAccuracy!.isNotEmpty)
                      _MetaInfoTile(emoji: '📐', label: 'GPS Accuracy', value: shape.gpsAccuracy!,
                        valueColor: const Color(0xFF43A047)),
                    if (shape.altitude != null && shape.altitude!.isNotEmpty)
                      _MetaInfoTile(emoji: '🧭', label: 'Altitude', value: shape.altitude!,
                        valueColor: const Color(0xFF43A047)),
                    _MetaInfoTile(
                      emoji: '📍', label: 'Coordinates',
                      value: 'Lat: ${shape.points.first.latitude.toStringAsFixed(6)}\n'
                          'Lng: ${shape.points.first.longitude.toStringAsFixed(6)}',
                    ),
                    if (shape.officerName != null && shape.officerName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _MetaInfoTile(emoji: '👤', label: 'Officer / Beat', value: shape.officerName!),
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
              spacing: 8, runSpacing: 8,
              children: [
                _ActionChip(
                  icon: Icons.edit, label: 'Edit',
                  onTap: () => setState(() => _editMode = true),
                ),
                _ActionChip(icon: Icons.palette, label: 'Color',
                  onTap: () => _showColorPicker(context)),
                _ActionChip(icon: Icons.save_alt, label: 'Save',
                  onTap: () => _saveShape(context)),
                _ActionChip(icon: Icons.share, label: 'Export KML',
                  onTap: () => _exportKml(context)),
                if (shape.type == DrawMode.path && shape.points.length > 2)
                  _ActionChip(
                    icon: Icons.auto_awesome_mosaic, label: 'To Polygon',
                    color: AppTheme.greenPrimary,
                    onTap: () async {
                      await controller.convertPathToPolygon(shape.id);
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${shape.name} converted to Polygon!'),
                          backgroundColor: AppTheme.greenPrimary,
                        ),
                      );
                    },
                  ),
                if (shape.type == DrawMode.polygon)
                  _ActionChip(icon: Icons.print, label: 'Print',
                    color: AppTheme.infoColor,
                    onTap: () => _printPdf(context)),
                _ActionChip(icon: Icons.delete_outline, label: 'Delete',
                  color: AppTheme.errorColor,
                  onTap: () => _deleteShape(context)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Utility helpers ────────────────────────────────────────────────────────

  IconData _shapeIcon(DrawMode type) {
    switch (type) {
      case DrawMode.polygon: return Icons.pentagon;
      case DrawMode.path: return Icons.polyline;
      case DrawMode.marker: return Icons.place;
      default: return Icons.shape_line;
    }
  }

  String _typeLabel(DrawMode type) {
    if (type == DrawMode.marker && shape.category != null) return shape.category!;
    switch (type) {
      case DrawMode.polygon: return 'Polygon';
      case DrawMode.path: return 'Path / Line';
      case DrawMode.marker: return 'Marker / Point';
      default: return 'Shape';
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

  void _showColorPicker(BuildContext context) {
    Color pickedColor = shape.color;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Choose Color', style: TextStyle(color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: shape.color,
            availableColors: AppTheme.polygonColors,
            onColorChanged: (c) => pickedColor = c,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
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
        content: Text(saved
            ? '${shape.name} saved to database'
            : 'Only polygons can be saved'),
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
            SnackBar(content: Text('KML saved to $outputPath'),
              backgroundColor: AppTheme.greenPrimary),
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
        const SnackBar(content: Text('Generating PDF...')));
      final pts = shape.points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      final path = await PdfGenerator.generatePolygonPdf(
        parts: [
          PolygonPart(
            name: shape.name, points: pts,
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
          SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  void _deleteShape(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Shape?',
          style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Delete "${shape.name}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
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

// ══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _EditLabel extends StatelessWidget {
  final String label;
  const _EditLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
    style: const TextStyle(color: AppTheme.textSecondary,
      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));
}

class _SectionRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SectionRow({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 64,
        child: Text(label, style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      ),
      Expanded(child: child),
    ]);
  }
}

class _FieldGroup extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldGroup({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      child,
    ]);
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) display;
  final void Function(T?) onChanged;
  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: AppTheme.bgCard,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
            color: AppTheme.textSecondary, size: 18),
          items: items.map((item) => DropdownMenuItem<T>(
            value: item,
            child: Text(display(item)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _ColorSwatch({required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100, height: 36,
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down_rounded,
            color: AppTheme.textSecondary, size: 18),
        ]),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OutlineButton({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolbarBtn({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Icon(icon, color: AppTheme.textSecondary, size: 18),
        ),
      ),
    );
  }
}

class _MoreSettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MoreSettingTile({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, color: AppTheme.textMuted, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
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
    required this.label, required this.value, required this.subValue,
    required this.icon, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(
            color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(subValue, style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 11)),
        ]),
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
    required this.icon, required this.label, required this.onTap,
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
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(
          color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _MetaInfoTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color? valueColor;
  const _MetaInfoTile({
    required this.emoji, required this.label, required this.value, this.valueColor,
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(
              color: valueColor ?? AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }
}

// ── Voice Note Player ─────────────────────────────────────────────────────────

class _VoiceNotePlayer extends StatefulWidget {
  final String path;
  const _VoiceNotePlayer({required this.path});
  @override
  State<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<_VoiceNotePlayer> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _stateSub, _posSub, _durSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.setSource(DeviceFileSource(widget.path));
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () async {
            if (isPlaying) {
              await _player.pause();
            } else {
              await _player.play(DeviceFileSource(widget.path));
            }
          },
          child: Container(
            width: 42, height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFF43A047), shape: BoxShape.circle),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🎙️', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              const Text('Voice Note', style: TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${_fmt(_position)} / ${_fmt(_duration)}',
                style: const TextStyle(
                  color: Color(0xFF43A047), fontSize: 11, fontFamily: 'monospace')),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF43A047)),
                minHeight: 4,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () async {
            await _player.stop();
            setState(() => _position = Duration.zero);
          },
          child: const Icon(Icons.stop_rounded, color: Colors.white38, size: 22),
        ),
      ]),
    );
  }
}
