import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../shared/theme.dart';
import '../../core/database/db_helper.dart';
import '../../core/models/village_model.dart';
import '../../core/utils/kml_engine.dart';
import '../../core/utils/geo_calculator.dart';
import 'village_detail_screen.dart';

class VillagesScreen extends StatefulWidget {
  const VillagesScreen({super.key});

  @override
  State<VillagesScreen> createState() => _VillagesScreenState();
}

class _VillagesScreenState extends State<VillagesScreen> {
  List<VillageModel> _villages = [];
  List<VillageModel> _filteredVillages = [];
  String _search = '';
  bool _isImporting = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadVillages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _updateFilter() {
    final q = _search.trim().toLowerCase();
    _filteredVillages = q.isEmpty
        ? _villages
        : _villages.where((v) {
            return v.villageName.toLowerCase().contains(q) ||
                v.district.toLowerCase().contains(q) ||
                v.state.toLowerCase().contains(q);
          }).toList();
  }

  Future<void> _loadVillages() async {
    final villages = await DbHelper().getAllVillages();
    if (mounted) {
      setState(() {
        _villages = villages;
        _updateFilter();
      });
    }
  }

  Future<void> _importFiles() async {
    if (_isImporting) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['kml', 'kmz', 'geojson', 'json'],
        withReadStream: false,
        withData: false,
      );
    } catch (e) {
      _showSnack('Failed to open file picker: $e', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;
    setState(() => _isImporting = true);
    _showSnack('Importing ${result.files.length} file(s)…');

    int imported = 0;
    int failed = 0;

    for (final file in result.files) {
      final path = file.path;
      if (path == null) { failed++; continue; }
      try {
        final ext = file.extension?.toLowerCase() ?? '';
        List<KmlShape> shapes;

        if (ext == 'geojson' || ext == 'json') {
          final content = await File(path).readAsString();
          shapes = KmlEngine.parseGeoJson(content);
        } else {
          shapes = await KmlEngine.parseFile(path);
        }

        if (shapes.isEmpty) { failed++; continue; }

        for (final shape in shapes) {
          final areaHa = GeoCalculator.calculateAreaHectares(shape.coordinates);
          final coordJson = jsonEncode(shape.coordinates);
          final village = VillageModel(
            villageName: shape.name.isNotEmpty ? shape.name : file.name,
            district: '',
            state: '',
            coordinates: coordJson,
            areaHectares: areaHa,
            sourceFile: file.name,
            createdAt: DateTime.now().toIso8601String(),
          );
          await DbHelper().insertVillage(village);
          imported++;
        }
      } catch (e) {
        failed++;
        debugPrint('Import error ${file.name}: $e');
      }
    }

    await _loadVillages();
    if (mounted) {
      setState(() => _isImporting = false);
      final msg = imported > 0
          ? 'Imported $imported village(s)${failed > 0 ? ', $failed failed' : ''}'
          : 'Import failed: no valid shapes found';
      _showSnack(msg, isError: imported == 0);
    }
  }

  Future<void> _deleteVillage(VillageModel v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Village Map?'),
        content: Text('Remove "${v.villageName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && v.id != null) {
      await DbHelper().deleteVillage(v.id!);
      await _loadVillages();
      _showSnack('${v.villageName} deleted');
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete All Villages?'),
        content: const Text('This will remove all imported village maps. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DbHelper().deleteAllVillages();
      await _loadVillages();
      _showSnack('All village maps deleted');
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
    final villages = _filteredVillages;
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Village Maps'),
        actions: [
          if (_villages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete All',
              onPressed: _deleteAll,
            ),
          IconButton(
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            tooltip: 'Import Village Map',
            onPressed: _isImporting ? null : _importFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search village, district...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                // Debounce: wait 200ms after last keystroke before refiltering
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                  setState(() {
                    _search = v;
                    _updateFilter();
                  });
                });
              },
            ),
          ),

          // Stats bar
          if (_villages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${villages.length} village${villages.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: villages.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadVillages,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      itemCount: villages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (ctx, i) {
                        final v = villages[i];
                        return _VillageCard(
                          village: v,
                          onTap: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) =>
                                  VillageDetailScreen(village: v),
                            ),
                          ),
                          onDelete: () => _deleteVillage(v),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _importFiles,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_location_alt),
        label: const Text('Import Map'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_city_outlined,
                size: 64, color: AppTheme.infoColor),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Village Maps Imported',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Import KML, KMZ, or GeoJSON files\ncontaining village boundary data',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importFiles,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import Village Maps'),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Tip: You can also import Shapefiles by converting them\nto GeoJSON using QGIS or mapshaper.org',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _VillageCard extends StatelessWidget {
  final VillageModel village;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _VillageCard({
    required this.village,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final area = GeoCalculator.formatArea(village.areaHectares);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Color dot
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.infoColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.infoColor, width: 1.5),
                ),
                child: const Icon(Icons.location_city,
                    color: AppTheme.infoColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      village.villageName,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    if (village.district.isNotEmpty ||
                        village.state.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [village.district, village.state]
                            .where((s) => s.isNotEmpty)
                            .join(', '),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.greenPrimary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            area,
                            style: const TextStyle(
                                color: AppTheme.greenAccent, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (village.sourceFile.isNotEmpty)
                          Text(
                            village.sourceFile,
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 10),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.errorColor, size: 18),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textMuted, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
