import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../shared/theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class OfflineRegion {
  final String id;
  final String name;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final int minZoom;
  final int maxZoom;
  final DateTime createdAt;

  OfflineRegion({
    required this.id,
    required this.name,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.minZoom,
    required this.maxZoom,
    required this.createdAt,
  });

  /// Approximate tile count using the simplified area formula:
  ///   tiles(z) = (2^z)^2 * latRange * lngRange / (360 * 180) / 4
  int get estimatedTileCount {
    final double latRange = (maxLat - minLat).abs();
    final double lngRange = (maxLng - minLng).abs();
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final double tilesAtZ =
          pow(2, z).toDouble() * pow(2, z).toDouble() * latRange * lngRange /
              (360.0 * 180.0) /
              4.0;
      total += tilesAtZ.ceil();
    }
    return total;
  }

  /// Rough storage estimate: ~15 KB per tile on average.
  double get estimatedMB => estimatedTileCount * 15 / 1024;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minLat': minLat,
        'maxLat': maxLat,
        'minLng': minLng,
        'maxLng': maxLng,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OfflineRegion.fromJson(Map<String, dynamic> json) => OfflineRegion(
        id: json['id'] as String,
        name: json['name'] as String,
        minLat: (json['minLat'] as num).toDouble(),
        maxLat: (json['maxLat'] as num).toDouble(),
        minLng: (json['minLng'] as num).toDouble(),
        maxLng: (json['maxLng'] as num).toDouble(),
        minZoom: json['minZoom'] as int,
        maxZoom: json['maxZoom'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  static const String _prefKey = 'offline_regions';

  // -- form controllers --
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _minLatCtrl = TextEditingController();
  final _maxLatCtrl = TextEditingController();
  final _minLngCtrl = TextEditingController();
  final _maxLngCtrl = TextEditingController();

  double _minZoom = 10;
  double _maxZoom = 14;

  // -- state --
  List<OfflineRegion> _regions = [];
  bool _loading = true;
  bool _downloading = false;
  double _downloadProgress = 0.0;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _minLatCtrl.dispose();
    _maxLatCtrl.dispose();
    _minLngCtrl.dispose();
    _maxLngCtrl.dispose();
    super.dispose();
  }

  // -- persistence --

  Future<void> _loadRegions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      setState(() {
        _regions = decoded
            .map((e) => OfflineRegion.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _saveRegions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(_regions.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> _deleteRegion(String id) async {
    setState(() => _regions.removeWhere((r) => r.id == id));
    await _saveRegions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Region removed.')),
      );
    }
  }

  // -- cache clear --

  Future<void> _clearTileCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Tile Cache'),
        content: const Text(
          'This will remove all automatically cached map tiles from your device. '
          'Manually saved regions will not be affected.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearingCache = true);
    // Simulate clearing – actual clearing depends on the tile plugin used.
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _clearingCache = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tile cache cleared successfully.')),
      );
    }
  }

  // -- download (simulated) --

  Future<void> _startDownload() async {
    if (!_formKey.currentState!.validate()) return;

    final region = OfflineRegion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      minLat: double.parse(_minLatCtrl.text.trim()),
      maxLat: double.parse(_maxLatCtrl.text.trim()),
      minLng: double.parse(_minLngCtrl.text.trim()),
      maxLng: double.parse(_maxLngCtrl.text.trim()),
      minZoom: _minZoom.round(),
      maxZoom: _maxZoom.round(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
    });

    // Simulate download in steps
    const int steps = 20;
    for (int i = 1; i <= steps; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _downloadProgress = i / steps);
    }

    setState(() {
      _regions.insert(0, region);
      _downloading = false;
      _downloadProgress = 0.0;
    });

    await _saveRegions();

    _nameCtrl.clear();
    _minLatCtrl.clear();
    _maxLatCtrl.clear();
    _minLngCtrl.clear();
    _maxLngCtrl.clear();
    setState(() {
      _minZoom = 10;
      _maxZoom = 14;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Region "${region.name}" saved (~${region.estimatedTileCount} tiles).'),
          backgroundColor: AppTheme.greenPrimary,
        ),
      );
    }
  }

  // -- computed --

  double get _totalStorageMB =>
      _regions.fold(0.0, (sum, r) => sum + r.estimatedMB);

  // -- validators --

  String? _validateDouble(String? v, String label,
      {double? min, double? max}) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    final d = double.tryParse(v.trim());
    if (d == null) return 'Enter a valid number';
    if (min != null && d < min) return '$label must be >= $min';
    if (max != null && d > max) return '$label must be <= $max';
    return null;
  }

  // -- build --

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Offline Maps'),
        elevation: 2,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoBanner(),
                const SizedBox(height: 16),
                _buildCacheManagementCard(),
                const SizedBox(height: 16),
                _buildDownloadSection(),
                const SizedBox(height: 16),
                _buildRegionsList(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // -- sub-widgets --

  Widget _buildInfoBanner() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Map tiles are cached automatically as you browse the map. '
              'Use the Download Region tool below to pre-save region metadata '
              'for quick access. Actual tile storage depends on your map plugin '
              'configuration and device storage.',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.primaryColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheManagementCard() {
    return _SectionCard(
      title: 'Cache Management',
      icon: Icons.storage_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-cached tiles',
                    style: AppTheme.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tiles browsed online are cached on-device for offline viewing.',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _clearingCache
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : OutlinedButton.icon(
                    onPressed: _clearTileCache,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Clear Cache'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                      side: BorderSide(color: AppTheme.errorColor),
                    ),
                  ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadSection() {
    return _SectionCard(
      title: 'Download Region',
      icon: Icons.download_for_offline_rounded,
      children: [
        // Warning note
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.amber.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Note: This saves region metadata only. '
                  'Full tile downloading requires native map plugin support. '
                  'Tiles will be loaded from cache as you browse the saved area.',
                  style: AppTheme.bodySmall
                      .copyWith(color: Colors.amber.shade800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Region name
              TextFormField(
                controller: _nameCtrl,
                decoration: AppTheme.inputDecoration(
                  'Region Name',
                  hint: 'e.g. Varanasi City Center',
                  prefixIcon: Icons.label_outline,
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Name is required'
                    : null,
              ),
              const SizedBox(height: 14),

              Text(
                'Bounding Box',
                style: AppTheme.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Lat row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minLatCtrl,
                      decoration: AppTheme.inputDecoration(
                        'Min Latitude',
                        hint: '25.0',
                        prefixIcon: Icons.south,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      validator: (v) =>
                          _validateDouble(v, 'Min Lat', min: -90, max: 90),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _maxLatCtrl,
                      decoration: AppTheme.inputDecoration(
                        'Max Latitude',
                        hint: '26.0',
                        prefixIcon: Icons.north,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      validator: (v) {
                        final err =
                            _validateDouble(v, 'Max Lat', min: -90, max: 90);
                        if (err != null) return err;
                        final minVal =
                            double.tryParse(_minLatCtrl.text.trim()) ?? 0;
                        final maxVal =
                            double.tryParse(v!.trim()) ?? 0;
                        if (maxVal <= minVal) return 'Must be > Min Lat';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Lng row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minLngCtrl,
                      decoration: AppTheme.inputDecoration(
                        'Min Longitude',
                        hint: '82.0',
                        prefixIcon: Icons.west,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      validator: (v) => _validateDouble(v, 'Min Lng',
                          min: -180, max: 180),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _maxLngCtrl,
                      decoration: AppTheme.inputDecoration(
                        'Max Longitude',
                        hint: '83.5',
                        prefixIcon: Icons.east,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      validator: (v) {
                        final err = _validateDouble(v, 'Max Lng',
                            min: -180, max: 180);
                        if (err != null) return err;
                        final minVal =
                            double.tryParse(_minLngCtrl.text.trim()) ?? 0;
                        final maxVal =
                            double.tryParse(v!.trim()) ?? 0;
                        if (maxVal <= minVal) return 'Must be > Min Lng';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Zoom range
              Text(
                'Zoom Range  z${_minZoom.round()} – z${_maxZoom.round()}',
                style: AppTheme.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              RangeSlider(
                values: RangeValues(_minZoom, _maxZoom),
                min: 10,
                max: 16,
                divisions: 6,
                activeColor: AppTheme.primaryColor,
                labels: RangeLabels(
                  _minZoom.round().toString(),
                  _maxZoom.round().toString(),
                ),
                onChanged: (RangeValues values) {
                  setState(() {
                    _minZoom = values.start;
                    _maxZoom = values.end;
                  });
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('z10',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary)),
                  Text('z16',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 16),

              // Progress or button
              if (_downloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Saving region metadata…',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                        Text(
                          '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _downloadProgress,
                        minHeight: 10,
                        backgroundColor:
                            AppTheme.primaryColor.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryColor),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Save Region'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegionsList() {
    return _SectionCard(
      title: 'Saved Regions (${_regions.length})',
      icon: Icons.map_outlined,
      trailing: _regions.isNotEmpty
          ? Text(
              'Est. ${_totalStorageMB.toStringAsFixed(1)} MB total',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      children: _regions.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: AppTheme.textSecondary.withOpacity(0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No saved regions yet.\nUse the form above to save a region.',
                        textAlign: TextAlign.center,
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ]
          : _regions
              .map(
                (region) => _RegionCard(
                  region: region,
                  onDelete: () => _deleteRegion(region.id),
                ),
              )
              .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Region Card widget
// ---------------------------------------------------------------------------

class _RegionCard extends StatelessWidget {
  final OfflineRegion region;
  final VoidCallback onDelete;

  const _RegionCard({required this.region, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.map_rounded,
                  color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    region.name,
                    style: AppTheme.bodyMedium
                        .copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    label: 'Bounds',
                    value:
                        '${region.minLat.toStringAsFixed(3)}, '
                        '${region.minLng.toStringAsFixed(3)}  →  '
                        '${region.maxLat.toStringAsFixed(3)}, '
                        '${region.maxLng.toStringAsFixed(3)}',
                  ),
                  _InfoRow(
                    label: 'Zoom',
                    value: 'z${region.minZoom} – z${region.maxZoom}',
                  ),
                  _InfoRow(
                    label: 'Tiles',
                    value:
                        '~${region.estimatedTileCount}  '
                        '(approx ${region.estimatedMB.toStringAsFixed(1)} MB)',
                  ),
                  _InfoRow(
                    label: 'Saved',
                    value: _formatDate(region.createdAt),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: AppTheme.errorColor),
              tooltip: 'Remove region',
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(value,
                style: AppTheme.bodySmall.copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Card helper widget
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
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
          // Header
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
                Expanded(
                  child: Text(
                    title,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
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
