import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/theme.dart';
import '../../core/database/db_helper.dart';

// ---------------------------------------------------------------------------
// Constants – SharedPreferences keys
// ---------------------------------------------------------------------------

class _Keys {
  static const orgName = 'settings_org_name';
  static const orgLogoPath = 'settings_org_logo_path';
  static const pageSize = 'settings_page_size';
  static const orientation = 'settings_orientation';
  static const polygonColor = 'settings_polygon_color';
  static const defaultZoom = 'settings_default_zoom';
  static const firmsApiKey = 'settings_firms_api_key';
  static const fireAlertRadius = 'settings_fire_alert_radius';
  static const cloudVisionApiKey = 'settings_cloud_vision_api_key';
}

// ---------------------------------------------------------------------------
// Settings Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // -- controllers --
  final _orgNameCtrl = TextEditingController();
  final _firmsApiKeyCtrl = TextEditingController();
  final _cloudVisionApiKeyCtrl = TextEditingController();

  // -- state --
  String _orgLogoPath = '';
  String _pageSize = 'A4';
  String _orientation = 'Portrait';
  Color _polygonColor = const Color(0xFF2196F3);
  double _defaultZoom = 13.0;
  double _fireAlertRadius = 5.0;

  bool _loading = true;
  bool _saving = false;

  static const List<String> _pageSizes = ['A4', 'A3', 'Letter'];
  static const List<String> _orientations = ['Portrait', 'Landscape'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _orgNameCtrl.dispose();
    _firmsApiKeyCtrl.dispose();
    _cloudVisionApiKeyCtrl.dispose();
    super.dispose();
  }

  // -- persistence --

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _orgNameCtrl.text = prefs.getString(_Keys.orgName) ?? '';
      _orgLogoPath = prefs.getString(_Keys.orgLogoPath) ?? '';
      _pageSize = prefs.getString(_Keys.pageSize) ?? 'A4';
      _orientation = prefs.getString(_Keys.orientation) ?? 'Portrait';
      final colorVal = prefs.getInt(_Keys.polygonColor);
      _polygonColor = colorVal != null
          ? Color(colorVal)
          : const Color(0xFF2196F3);
      _defaultZoom = prefs.getDouble(_Keys.defaultZoom) ?? 13.0;
      _firmsApiKeyCtrl.text = prefs.getString(_Keys.firmsApiKey) ?? '';
      _fireAlertRadius = prefs.getDouble(_Keys.fireAlertRadius) ?? 5.0;
      _cloudVisionApiKeyCtrl.text = prefs.getString(_Keys.cloudVisionApiKey) ?? '';
      _loading = false;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  // -- actions --

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path ?? '';
      setState(() => _orgLogoPath = path);
      await _saveSetting(_Keys.orgLogoPath, path);
    }
  }

  Future<void> _pickPolygonColor() async {
    Color temp = _polygonColor;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Default Polygon Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _polygonColor,
            onColorChanged: (c) => temp = c,
            enableAlpha: true,
            labelTypes: const [ColorLabelType.rgb, ColorLabelType.hex],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.greenPrimary),
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Select',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    setState(() => _polygonColor = temp);
    await _saveSetting(_Keys.polygonColor, temp.value);
  }

  Future<void> _exportAllPolygonsAsKml() async {
    setState(() => _saving = true);
    try {
      // Placeholder: actual KML export requires reading polygons from DB.
      // This generates a minimal KML skeleton.
      const kmlContent = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>KashiGeoField Pro Export</name>
  </Document>
</kml>''';

      await Share.share(kmlContent,
          subject: 'KashiGeoField Pro - Polygon Export');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearAllShapes() async {
    final confirmed = await _confirmDialog(
      title: 'Clear All Drawn Shapes',
      message:
          'This will permanently delete all drawn polygons and shapes from the database. '
          'This action cannot be undone.\n\nAre you sure?',
      confirmLabel: 'Clear All',
      isDestructive: true,
    );
    if (!confirmed) return;

    await DbHelper().clearAllPolygons();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All shapes cleared.')),
      );
    }
  }

  Future<void> _clearPrintHistory() async {
    final confirmed = await _confirmDialog(
      title: 'Clear Print History',
      message: 'Delete all print history records?\n\nThis cannot be undone.',
      confirmLabel: 'Clear',
      isDestructive: true,
    );
    if (!confirmed) return;

    await DbHelper().clearPrintHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print history cleared.')),
      );
    }
  }

  Future<void> _viewPrintHistory() async {
    final history = await DbHelper().getPrintHistory();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.history, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('Print History'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: history.isEmpty
              ? const Center(child: Text('No print history found.'))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final record = history[index];
                    final title = record.mapName.isNotEmpty ? record.mapName : 'Print #${index + 1}';
                    final date = record.printedAt.length >= 10 ? record.printedAt.substring(0, 10) : record.printedAt;
                    final path = record.pdfPath;
                    return ListTile(
                      leading: Icon(Icons.print_outlined,
                          color: AppTheme.primaryColor, size: 20),
                      title: Text(title,
                          style: AppTheme.bodySmall
                              .copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(date,
                          style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                              fontSize: 11)),
                      trailing: path.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.share, size: 20),
                              tooltip: 'Share',
                              onPressed: () => Share.shareXFiles(
                                [XFile(path)],
                                subject: title,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.share, size: 20),
                              tooltip: 'Share',
                              onPressed: () => Share.share(title),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDestructive ? AppTheme.errorColor : AppTheme.primaryColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // -- build --

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 2,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOrganizationSection(),
                const SizedBox(height: 16),
                _buildPrintSection(),
                const SizedBox(height: 16),
                _buildMapSection(),
                const SizedBox(height: 16),
                  _buildFireAlertSection(),
                  const SizedBox(height: 24),
                  _buildOcrSection(),
                  const SizedBox(height: 24),
                  _buildDataManagementSection(),
                const SizedBox(height: 16),
                _buildAppInfoSection(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1 – Organization Settings
  // ---------------------------------------------------------------------------

  Widget _buildOrganizationSection() {
    return _SettingsCard(
      title: 'Organization',
      icon: Icons.business_rounded,
      children: [
        TextField(
          controller: _orgNameCtrl,
          decoration: AppTheme.inputDecoration(
            'Organization Name',
            hint: 'e.g. Varanasi Survey Department',
            prefixIcon: Icons.business_outlined,
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => _saveSetting(_Keys.orgName, v.trim()),
        ),
        const SizedBox(height: 14),
        _SettingRow(
          label: 'Organization Logo',
          subtitle: _orgLogoPath.isEmpty
              ? 'No logo selected'
              : _orgLogoPath.split(RegExp(r'[/\\]')).last,
          trailing: OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Browse'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(color: AppTheme.primaryColor),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2 – Print Settings
  // ---------------------------------------------------------------------------

  Widget _buildPrintSection() {
    return _SettingsCard(
      title: 'Print Settings',
      icon: Icons.print_rounded,
      children: [
        _SettingRow(
          label: 'Page Size',
          subtitle: 'Paper size for printed maps',
          trailing: DropdownButton<String>(
            value: _pageSize,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(8),
            items: _pageSizes
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, style: AppTheme.bodyMedium),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _pageSize = v);
              _saveSetting(_Keys.pageSize, v);
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          label: 'Orientation',
          subtitle: 'Page orientation for prints',
          trailing: DropdownButton<String>(
            value: _orientation,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(8),
            items: _orientations
                .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(o, style: AppTheme.bodyMedium),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _orientation = v);
              _saveSetting(_Keys.orientation, v);
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 3 – Map Settings
  // ---------------------------------------------------------------------------

  Widget _buildMapSection() {
    return _SettingsCard(
      title: 'Map Settings',
      icon: Icons.map_rounded,
      children: [
        _SettingRow(
          label: 'Default Polygon Color',
          subtitle: 'Color applied to newly drawn polygons',
          trailing: GestureDetector(
            onTap: _pickPolygonColor,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _polygonColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _polygonColor.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.colorize_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ),
        const Divider(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Default Map Zoom',
                  style: AppTheme.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _defaultZoom.toStringAsFixed(1),
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Initial zoom when opening the map view',
              style: AppTheme.bodySmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
            Slider(
              value: _defaultZoom,
              min: 8.0,
              max: 18.0,
              divisions: 20,
              activeColor: AppTheme.primaryColor,
              label: _defaultZoom.toStringAsFixed(1),
              onChanged: (v) {
                setState(() => _defaultZoom = v);
              },
              onChangeEnd: (v) => _saveSetting(_Keys.defaultZoom, v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('z8 (Country)',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary, fontSize: 11)),
                Text('z18 (Street)',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 3.5 - Fire Alerts
  // ---------------------------------------------------------------------------

  Widget _buildFireAlertSection() {
    return _SettingsCard(
      title: 'Fire Detection Alerts',
      icon: Icons.local_fire_department_rounded,
      children: [
        _SettingRow(
          label: 'NASA FIRMS API Key',
          subtitle: 'Required for real-time fire detection',
          trailing: Expanded(
            child: TextField(
              controller: _firmsApiKeyCtrl,
              obscureText: true,
              style: AppTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Enter Map Key...',
                isDense: true,
                filled: true,
                fillColor: AppTheme.textSecondary.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => _saveSetting(_Keys.firmsApiKey, v.trim()),
            ),
          ),
        ),
        const Divider(height: 24),
        _SettingRow(
          label: 'Alert Radius (km)',
          subtitle: 'Warn if fires are within ${_fireAlertRadius.toStringAsFixed(1)} km of your saved areas',
          trailing: Expanded(
            child: Slider(
              value: _fireAlertRadius,
              min: 1.0,
              max: 20.0,
              divisions: 19,
              label: '${_fireAlertRadius.toStringAsFixed(1)} km',
              activeColor: const Color(0xFFD32F2F),
              onChanged: (v) {
                setState(() => _fireAlertRadius = v);
                _saveSetting(_Keys.fireAlertRadius, v);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 3.6 - OCR API
  // ---------------------------------------------------------------------------

  Widget _buildOcrSection() {
    return _SettingsCard(
      title: 'Google AI (Gemini)',
      icon: Icons.auto_awesome,
      children: [
        _SettingRow(
          label: 'Google AI API Key',
          subtitle: 'Required for "Ask AI" (PDF chat). Get FREE key at aistudio.google.com',
          trailing: Expanded(
            child: TextField(
              controller: _cloudVisionApiKeyCtrl,
              obscureText: true,
              style: AppTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Enter API Key...',
                isDense: true,
                filled: true,
                fillColor: AppTheme.textSecondary.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => _saveSetting(_Keys.cloudVisionApiKey, v.trim()),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 4 – Data Management
  // ---------------------------------------------------------------------------

  Widget _buildDataManagementSection() {
    return _SettingsCard(
      title: 'Data Management',
      icon: Icons.folder_special_rounded,
      children: [
        _ActionTile(
          icon: Icons.download_rounded,
          iconColor: const Color(0xFF1565C0),
          label: 'Export All Polygons as KML',
          subtitle: 'Share all drawn polygons in KML format',
          onTap: _saving ? null : _exportAllPolygonsAsKml,
          isLoading: _saving,
        ),
        const Divider(height: 20),
        _ActionTile(
          icon: Icons.layers_clear_rounded,
          iconColor: const Color(0xFFE65100),
          label: 'Clear All Drawn Shapes',
          subtitle: 'Permanently removes all polygons from the database',
          onTap: _clearAllShapes,
          isDestructive: true,
        ),
        const Divider(height: 20),
        _ActionTile(
          icon: Icons.delete_forever_rounded,
          iconColor: AppTheme.errorColor,
          label: 'Clear Print History',
          subtitle: 'Remove all saved print records',
          onTap: _clearPrintHistory,
          isDestructive: true,
        ),
        const Divider(height: 20),
        _ActionTile(
          icon: Icons.history_rounded,
          iconColor: const Color(0xFF6A1B9A),
          label: 'View Print History',
          subtitle: 'Browse and share previous print records',
          onTap: _viewPrintHistory,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 5 – App Info
  // ---------------------------------------------------------------------------

  Widget _buildAppInfoSection() {
    return _SettingsCard(
      title: 'App Info',
      icon: Icons.info_outline_rounded,
      children: [
        _InfoTile(label: 'App Name', value: 'KashiGeoField Pro'),
        const Divider(height: 16),
        _InfoTile(label: 'Version', value: '1.0.0 (build 1)'),
        const Divider(height: 16),
        _InfoTile(label: 'Developer', value: 'KashiGeo Technologies'),
        const Divider(height: 16),
        _InfoTile(
            label: 'Description',
            value: 'Professional GIS field data collection and mapping tool '
                'for surveyors and engineers.'),
        const Divider(height: 16),
        _InfoTile(label: 'Contact', value: 'support@kashigeo.example.com'),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Copyright (c) 2024 KashiGeo Technologies.\nAll rights reserved.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings Card wrapper
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
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

// ---------------------------------------------------------------------------
// Reusable setting widgets
// ---------------------------------------------------------------------------

/// A row with label/subtitle on the left and arbitrary trailing widget.
class _SettingRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.label,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

/// An action tile (button-style row) for data-management operations.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isLoading;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.isDestructive = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? AppTheme.errorColor : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple key-value info row.
class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: AppTheme.bodySmall),
        ),
      ],
    );
  }
}
